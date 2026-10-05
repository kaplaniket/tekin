#!/usr/bin/env bash
# Richtet den Jev-Agent (TypeSafe) fuer den aktuellen Benutzer ein.
# Laeuft auf dem Cloud-Server (Benutzer hermes) und direkt auf dem Pi (Benutzer tekin).
# Nicht als root ausfuehren:  ./cloud/jev/install-jev.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/.local/share/jev-agent"
BIN="$HOME/.local/bin"
MARKER="# jev-agent wrapper"

if [ "$(id -u)" -eq 0 ]; then
    echo "Bitte nicht als root ausfuehren, sondern als der Benutzer, der Hermes betreibt." >&2
    exit 1
fi

echo "==> Python-Umgebung mit typesafe-sdk anlegen"
mkdir -p "$APP"
if command -v uv >/dev/null || [ -x "$BIN/uv" ]; then
    UV="$(command -v uv || echo "$BIN/uv")"
    "$UV" venv --quiet --allow-existing "$APP/venv"
    "$UV" pip install --quiet --python "$APP/venv/bin/python" --upgrade typesafe-sdk "mcp>=1.10,<2"
else
    python3 -m venv "$APP/venv"
    "$APP/venv/bin/pip" install --quiet --upgrade typesafe-sdk "mcp>=1.10,<2"
fi
install -m 755 "$HERE/jev_agent.py" "$APP/jev_agent.py"
install -m 644 "$HERE/beispiel.json" "$APP/beispiel.json"
install -m 755 "$HERE/jev_mcp.py" "$APP/jev_mcp.py"

echo "==> Hermes-Skill jev nach ~/.hermes/skills/jev"
install -d "$HOME/.hermes/skills/jev"
install -m 644 "$HERE/SKILL.md" "$HOME/.hermes/skills/jev/SKILL.md"

# Einen vorhandenen fremden `jev`-Befehl nicht ueberschreiben.
NAME="jev"
if [ -e "$BIN/jev" ] && ! grep -qF "$MARKER" "$BIN/jev" 2>/dev/null; then
    NAME="jev-ts"
    echo "Hinweis: $BIN/jev gibt es schon (anderes Programm) - lege den Befehl als '$NAME' an."
elif command -v jev >/dev/null && [ "$(command -v jev)" != "$BIN/jev" ]; then
    NAME="jev-ts"
    echo "Hinweis: '$(command -v jev)' gibt es schon - lege den Befehl als '$NAME' an."
fi

mkdir -p "$BIN"
cat > "$BIN/$NAME" <<EOF
#!/usr/bin/env bash
$MARKER
# Nur die TYPESAFE_*-Zeilen uebernehmen, die restliche .env wird nicht ausgefuehrt.
if [ -f "\$HOME/.hermes/.env" ]; then
    while IFS== read -r key value; do
        value="\${value%[\"\']}"; value="\${value#[\"\']}"
        export "\$key=\$value"
    done < <(grep -E '^TYPESAFE_[A-Z_]+=' "\$HOME/.hermes/.env")
fi
exec "$APP/venv/bin/python" "$APP/jev_agent.py" "\$@"
EOF
chmod 755 "$BIN/$NAME"

echo "==> systemd-User-Dienst jev-agent (nur 127.0.0.1:8765)"
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/jev-agent.service" <<EOF
[Unit]
Description=Jev-Agent (TypeSafe System One)
After=network-online.target

[Service]
EnvironmentFile=%h/.hermes/.env
ExecStart=$APP/venv/bin/python $APP/jev_agent.py serve --host 127.0.0.1 --port 8765
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload

if grep -qE '^TYPESAFE_API_KEY=.+' "$HOME/.hermes/.env" 2>/dev/null; then
    systemctl --user enable --now jev-agent
    echo "Jev-Agent laeuft. Test:  $NAME ask $APP/beispiel.json"
else
    echo "TYPESAFE_API_KEY fehlt in ~/.hermes/.env - eintragen, dann:"
    echo "  systemctl --user enable --now jev-agent"
fi

echo
echo "Hermes an Jev anbinden (einmalig, fragt nach den Werkzeugen - einfach bestaetigen):"
echo "  hermes mcp add jev --command $APP/venv/bin/python --args $APP/jev_mcp.py"
echo "Danach Hermes neu starten (z. B. hermes gateway restart) und testen: hermes mcp test jev"
