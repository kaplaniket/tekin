#!/usr/bin/env bash
# Richtet den Jev-Agent (TypeSafe) fuer den Agent-Benutzer ein.
# Als Agent-Benutzer ausfuehren (nicht als root):  ~/tekin/cloud/jev/install-jev.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/.local/share/jev-agent"

command -v uv >/dev/null || { echo "uv fehlt - zuerst cloud/install.sh ausfuehren." >&2; exit 1; }

echo "==> Python-Umgebung mit typesafe-sdk anlegen"
uv venv --quiet --allow-existing "$APP/venv"
uv pip install --quiet --python "$APP/venv/bin/python" --upgrade typesafe-sdk
install -m 755 "$HERE/jev_agent.py" "$APP/jev_agent.py"

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/jev" <<EOF
#!/usr/bin/env bash
set -a; [ -f "\$HOME/.hermes/.env" ] && . "\$HOME/.hermes/.env"; set +a
exec "$APP/venv/bin/python" "$APP/jev_agent.py" "\$@"
EOF
chmod 755 "$HOME/.local/bin/jev"

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
    echo "Jev-Agent laeuft. Test:  jev ask $HERE/beispiel.json"
else
    echo "TYPESAFE_API_KEY fehlt in ~/.hermes/.env - eintragen, dann:"
    echo "  systemctl --user enable --now jev-agent"
fi
