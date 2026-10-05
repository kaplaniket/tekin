#!/usr/bin/env bash
# Installiert Tekins Agenten auf einem frischen Cloud-Server (Debian/Ubuntu):
#   - Hermes Agent (NousResearch) inkl. Gateway als Dauerdienst (systemd --user)
#   - Prime CLI / Prime Agent (Prime Intellect) als One-Shot-Werkzeug, kein Dauerprozess
#   - Jev-Agent (TypeSafe System One) als CLI `jev` und lokaler Dienst
#   - optional Tailscale, damit Pi, iMac und Cloud-Server sich im selben Netz sehen
#
# Aufruf als root auf dem Server:
#   curl -fsSL https://raw.githubusercontent.com/kaplaniket/tekin/main/cloud/install.sh | sudo bash
# oder nach git clone:
#   sudo ./cloud/install.sh [--user hermes] [--no-tailscale] [--no-prime] [--no-gateway] [--no-jev]
set -euo pipefail

AGENT_USER="hermes"
WITH_TAILSCALE=true
WITH_PRIME=true
WITH_GATEWAY=true
WITH_JEV=true
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

while [ $# -gt 0 ]; do
    case "$1" in
        --user) AGENT_USER="$2"; shift 2 ;;
        --no-tailscale) WITH_TAILSCALE=false; shift ;;
        --no-prime) WITH_PRIME=false; shift ;;
        --no-gateway) WITH_GATEWAY=false; shift ;;
        --no-jev) WITH_JEV=false; shift ;;
        -h|--help) sed -n 2,11p "$0"; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    esac
done

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "Bitte als root ausfuehren (sudo)." >&2
    exit 1
fi
if ! command -v apt-get >/dev/null; then
    echo "Nur Debian/Ubuntu wird unterstuetzt." >&2
    exit 1
fi

log "Systempakete installieren"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl git ca-certificates build-essential rsync tmux jq ufw >/dev/null

log "Benutzer '$AGENT_USER' anlegen"
if ! id "$AGENT_USER" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "$AGENT_USER"
fi
AGENT_HOME="$(getent passwd "$AGENT_USER" | cut -d: -f6)"
# Damit systemd --user-Dienste (Hermes-Gateway) ohne Login weiterlaufen.
loginctl enable-linger "$AGENT_USER"

as_agent() {
    sudo -u "$AGENT_USER" -H env XDG_RUNTIME_DIR="/run/user/$(id -u "$AGENT_USER")" \
        PATH="$AGENT_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" bash -lc "$1"
}

# Repo-Kopie im Home des Agent-Benutzers, damit z. B. ~/tekin/cloud/migrate-from-pi.sh existiert,
# auch wenn das Repo als root geklont wurde.
REPO_DIR="$(readlink -f "$SCRIPT_DIR/..")"
if [ -d "$SCRIPT_DIR/jev" ] && [ "$REPO_DIR" != "$AGENT_HOME/tekin" ]; then
    install -d -o "$AGENT_USER" -g "$AGENT_USER" "$AGENT_HOME/tekin"
    rsync -a --chown="$AGENT_USER:$AGENT_USER" --exclude .git "$REPO_DIR"/ "$AGENT_HOME/tekin"/
fi

log "Firewall: nur SSH von aussen erlauben"
ufw allow OpenSSH >/dev/null
ufw --force enable >/dev/null

if $WITH_TAILSCALE; then
    log "Tailscale installieren"
    if ! command -v tailscale >/dev/null; then
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    if [ -n "${TS_AUTHKEY:-}" ]; then
        tailscale up --authkey "$TS_AUTHKEY" --ssh --hostname "${TS_HOSTNAME:-hermes-cloud}"
    else
        echo "Kein TS_AUTHKEY gesetzt - spaeter manuell: sudo tailscale up --ssh"
    fi
fi

log "uv installieren"
as_agent 'command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh'

log "Hermes Agent installieren"
as_agent 'curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --non-interactive --skip-browser'

if $WITH_PRIME; then
    log "Prime CLI (Prime Intellect) installieren"
    as_agent 'uv tool install --upgrade prime'
fi

if $WITH_JEV; then
    log "Jev-Agent (TypeSafe) installieren"
    JEV_SRC="$AGENT_HOME/.local/share/jev-agent-src"
    if [ -d "$SCRIPT_DIR/jev" ]; then
        install -d -o "$AGENT_USER" -g "$AGENT_USER" "$JEV_SRC"
        install -o "$AGENT_USER" -g "$AGENT_USER" -m 755 "$SCRIPT_DIR"/jev/* "$JEV_SRC"/
        as_agent "$JEV_SRC/install-jev.sh" \
            || echo "Jev-Installation fehlgeschlagen - Meldung oben lesen, dann $JEV_SRC/install-jev.sh als $AGENT_USER erneut ausfuehren."
    else
        echo "cloud/jev nicht gefunden - Repo klonen und cloud/jev/install-jev.sh ausfuehren."
    fi
fi

if [ ! -f "$AGENT_HOME/.hermes/.env" ]; then
    log ".env-Vorlage anlegen"
    install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 700 "$AGENT_HOME/.hermes"
    install -o "$AGENT_USER" -g "$AGENT_USER" -m 600 \
        "$SCRIPT_DIR/env.example" "$AGENT_HOME/.hermes/.env" 2>/dev/null \
        || echo "env.example nicht gefunden - .env bitte manuell anlegen."
fi

if $WITH_GATEWAY; then
    log "Hermes-Gateway als Dienst einrichten"
    as_agent 'hermes gateway install' \
        || echo "Gateway-Dienst noch nicht aktiv - zuerst konfigurieren (siehe unten)."
fi

log "Fertig"
cat <<EOF

Naechste Schritte (als '$AGENT_USER': sudo -iu $AGENT_USER):
  1. Daten vom Pi uebernehmen (optional):   ~/tekin/cloud/migrate-from-pi.sh <pi-host>
     oder API-Schluessel eintragen:         nano ~/.hermes/.env
  2. Modell/Provider waehlen:               hermes model     (oder: hermes setup)
  3. Telegram & Co. verbinden:              hermes gateway setup
  4. Gateway starten und pruefen:           hermes gateway install && hermes doctor
  5. Prime anmelden:                        prime login
  6. Jev: TYPESAFE_API_KEY in ~/.hermes/.env, dann
     systemctl --user enable --now jev-agent && jev ask ~/.local/share/jev-agent/beispiel.json
EOF
