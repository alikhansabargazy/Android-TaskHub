#!/usr/bin/env bash
set -euo pipefail

# Run from macOS with Flutter installed. Password is entered by ssh/scp.
DEPLOY_DOMAIN="${1:-}"
SSH_HOST="51.77.53.215"
SSH_PORT="2977"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! "$DEPLOY_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
  echo "Usage: $0 app.example.com" >&2
  echo "Point the domain's A record to $SSH_HOST before deploying." >&2
  exit 2
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required on this Mac. Add flutter/bin to PATH." >&2
  exit 2
fi
if ! command -v ssh >/dev/null 2>&1 || ! command -v scp >/dev/null 2>&1; then
  echo "macOS ssh and scp commands are required." >&2
  exit 2
fi

cd "$PROJECT_ROOT"
flutter pub get
flutter analyze
flutter test
flutter build web --release
python3 -m unittest discover -s backend/tests -q

ARCHIVE="$(mktemp -t taskhub-release)"
trap 'rm -f "$ARCHIVE"' EXIT
tar -czf "$ARCHIVE" -C "$PROJECT_ROOT" backend -C "$PROJECT_ROOT/build" web

printf 'Uploading web app and API to %s...\n' "$SSH_HOST"
scp -P "$SSH_PORT" "$ARCHIVE" "root@$SSH_HOST:/tmp/taskhub-release.tar.gz"
ssh -T -p "$SSH_PORT" "root@$SSH_HOST" bash -s -- "$DEPLOY_DOMAIN" <<'REMOTE'
set -euo pipefail
DOMAIN="$1"
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
  echo 'Invalid domain.' >&2
  exit 2
fi
if ! command -v apt-get >/dev/null 2>&1 || ! command -v systemctl >/dev/null 2>&1; then
  echo 'This deployment script requires Debian/Ubuntu with systemd.' >&2
  exit 2
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3 caddy
python3 - <<'PY'
import sys
if sys.version_info < (3, 10):
    raise SystemExit('TaskHub API requires Python 3.10 or newer on the VPS.')
PY

id taskhub >/dev/null 2>&1 || useradd --system --home-dir /var/lib/taskhub --shell /usr/sbin/nologin taskhub
install -d -o taskhub -g taskhub -m 750 /var/lib/taskhub
install -d -o root -g root -m 755 /opt/taskhub
# Stop the API while replacing code; keep the SQLite database in /var/lib/taskhub.
systemctl stop taskhub.service 2>/dev/null || true
rm -rf /opt/taskhub/backend /opt/taskhub/web
mkdir -p /opt/taskhub
 tar -xzf /tmp/taskhub-release.tar.gz -C /opt/taskhub
rm -f /tmp/taskhub-release.tar.gz
chmod -R a+rX /opt/taskhub

cat >/etc/systemd/system/taskhub.service <<'SERVICE'
[Unit]
Description=TaskHub web and API
After=network.target

[Service]
Type=simple
User=taskhub
Group=taskhub
WorkingDirectory=/opt/taskhub
Environment=TASKHUB_DB=/var/lib/taskhub/taskhub.sqlite3
Environment=TASKHUB_WEB_DIR=/opt/taskhub/web
Environment=TASKHUB_HOST=127.0.0.1
Environment=TASKHUB_PORT=8000
ExecStart=/usr/bin/python3 -m backend.app
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/taskhub

[Install]
WantedBy=multi-user.target
SERVICE

install -d -m 755 /etc/caddy/Caddyfile.d
cat >/etc/caddy/Caddyfile.d/taskhub.caddy <<CADDY
$DOMAIN {
    encode zstd gzip
    reverse_proxy 127.0.0.1:8000
}
CADDY
if ! grep -Fqx 'import /etc/caddy/Caddyfile.d/*.caddy' /etc/caddy/Caddyfile; then
  cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.backup.$(date +%Y%m%d%H%M%S)"
  printf '\nimport /etc/caddy/Caddyfile.d/*.caddy\n' >> /etc/caddy/Caddyfile
fi
caddy validate --config /etc/caddy/Caddyfile
systemctl daemon-reload
systemctl enable --now taskhub.service
systemctl restart taskhub.service
systemctl enable --now caddy.service
systemctl restart caddy.service
for attempt in 1 2 3 4 5; do
  if curl --fail --silent http://127.0.0.1:8000/health; then break; fi
  sleep 2
done
curl --fail --silent http://127.0.0.1:8000/health >/dev/null
printf '\nDeployed: https://%s\n' "$DOMAIN"
REMOTE

printf '\nChecking public HTTPS endpoint...\n'
for attempt in 1 2 3 4 5 6; do
  if curl --fail --silent --show-error --max-time 15 "https://$DEPLOY_DOMAIN/health"; then
    printf '\nTaskHub is available at https://%s\n' "$DEPLOY_DOMAIN"
    exit 0
  fi
  sleep 5
done
echo "Deployment finished, but public HTTPS is not ready. Check DNS, ports 80/443 and Caddy logs." >&2
exit 1
