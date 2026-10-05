#!/usr/bin/env bash
# Uebernimmt Hermes-Konfiguration, Memory, Skills und .env vom Raspberry Pi
# auf den Cloud-Server. Als Agent-Benutzer auf dem Cloud-Server ausfuehren:
#   ./migrate-from-pi.sh pi@raspberrypi     (Tailscale-Name oder IP)
#
# Der Code (~/.hermes/hermes-agent) wird nicht kopiert - der Cloud-Server hat
# seine eigene Installation. Der Pi laeuft danach unveraendert weiter.
set -euo pipefail

PI="${1:?Aufruf: $0 <user@pi-host>}"

if systemctl --user is-active --quiet hermes-gateway 2>/dev/null; then
    echo "Gateway laeuft hier bereits - wird waehrend der Uebernahme gestoppt."
    systemctl --user stop hermes-gateway
fi

mkdir -p ~/.hermes
rsync -az --info=progress2 \
    --exclude 'hermes-agent/' \
    --exclude 'logs/' \
    --exclude '*.lock' \
    --exclude '__pycache__/' \
    "$PI:.hermes/" ~/.hermes/
chmod 600 ~/.hermes/.env 2>/dev/null || true

cat <<'EOF'

Uebernahme fertig. Wichtig:
  - Ein Telegram-Bot darf nur von EINEM Gateway gepollt werden. Auf dem Pi
    vorher stoppen:  ssh <pi> 'hermes gateway stop'
  - Dann hier starten:  hermes gateway install && hermes doctor
EOF
