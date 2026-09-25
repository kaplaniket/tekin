# Agenten auf dem Cloud-Server

Richtet Hermes Agent und Prime Agent auf einem frischen Debian/Ubuntu-Server ein
(Hetzner, DigitalOcean, AWS usw.; 2 vCPU / 4 GB RAM reichen).

| Agent | Wie er laeuft |
|---|---|
| **Hermes Agent** | Dauerdienst: `hermes gateway` als systemd-User-Service (Telegram usw.) |
| **Prime Agent / Prime CLI** | nur auf Abruf (One-Shot), kein Dauerprozess |
| **Tailscale** (optional) | verbindet Cloud-Server, Pi und iMac in einem privaten Netz |

## Installation

```bash
ssh root@<server-ip>
git clone https://github.com/kaplaniket/tekin.git && cd tekin
TS_AUTHKEY=tskey-... ./cloud/install.sh      # ohne Tailscale: --no-tailscale
```

Optionen: `--user <name>` (Standard: `hermes`), `--no-tailscale`, `--no-prime`, `--no-gateway`.

## Danach

```bash
sudo -iu hermes
~/tekin/cloud/migrate-from-pi.sh pi@raspberrypi   # optional: Memory, Skills, .env vom Pi holen
hermes model                                      # oder: nano ~/.hermes/.env
hermes gateway setup
hermes gateway install && hermes doctor
prime login
```

## Sicherheit

- Die Firewall erlaubt von aussen nur SSH. Das Hermes-Dashboard (Port 9119) nur
  per Tunnel oeffnen: `ssh -L 9119:localhost:9119 hermes@<server>`.
- `~/.hermes/.env` enthaelt die Schluessel (Rechte `600`) und gehoert nicht ins Repo.
- Ein Telegram-Bot kann nur von einem Gateway gleichzeitig abgefragt werden. Vor dem
  Start in der Cloud das Gateway auf dem Pi stoppen.
