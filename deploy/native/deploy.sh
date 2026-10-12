#!/usr/bin/env bash
# Выкладка на сервер без Docker: ./deploy/native/deploy.sh ubuntu@host [ssh-ключ]
# Первый запуск ставит uv, Caddy и сервис, следующие только обновляют код и сайт.
set -euo pipefail

HOST="${1:?Использование: deploy.sh ubuntu@host [ключ]}"
KEY="${2:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SSH=(ssh ${KEY:+-i "$KEY"})
RSYNC_SSH="ssh${KEY:+ -i $KEY}"

(cd "$ROOT/app" && flutter build web --release --no-web-resources-cdn)

STAGE=/tmp/rake-diary-upload
"${SSH[@]}" "$HOST" "rm -rf $STAGE && mkdir -p $STAGE"
rsync -az --delete -e "$RSYNC_SSH" \
  --exclude .venv --exclude __pycache__ --exclude '*.db*' --exclude .pytest_cache --exclude .ruff_cache --exclude tests \
  "$ROOT/backend" "$ROOT/data" "$ROOT/deploy/native" "$HOST:$STAGE/"
rsync -az --delete -e "$RSYNC_SSH" "$ROOT/app/build/web/" "$HOST:$STAGE/web/"

"${SSH[@]}" "$HOST" sudo bash -s <<'REMOTE'
set -euo pipefail
STAGE=/tmp/rake-diary-upload
APP=/opt/rake-diary

id rakediary >/dev/null 2>&1 || useradd --system --home-dir "$APP" --shell /usr/sbin/nologin rakediary

if ! command -v uv >/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh
fi
if ! command -v caddy >/dev/null; then
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update && apt-get install -y caddy
  mkdir -p /etc/systemd/system/caddy.service.d
  printf '[Service]\nMemoryMax=128M\n' > /etc/systemd/system/caddy.service.d/limits.conf
fi

mkdir -p "$APP"
rsync -a --delete --exclude .venv "$STAGE/backend/" "$APP/backend/"
rsync -a --delete "$STAGE/data/" "$APP/data/"
rsync -a --delete "$STAGE/web/" "$APP/web/"
cd "$APP/backend"
UV_PYTHON_DOWNLOADS=never UV_PYTHON=python3 UV_CACHE_DIR=/var/cache/rake-diary-uv \
  uv sync --locked --no-dev --compile-bytecode
rm -rf /var/cache/rake-diary-uv
chown -R root:root "$APP"
chmod -R go-w "$APP"

install -m 644 "$STAGE/native/rake-diary.service" /etc/systemd/system/rake-diary.service
install -m 644 "$STAGE/native/Caddyfile" /etc/caddy/Caddyfile
systemctl daemon-reload
systemctl enable --now rake-diary
systemctl restart rake-diary caddy

ufw allow 80/tcp >/dev/null
ufw allow 443 >/dev/null
rm -rf "$STAGE"

for _ in $(seq 1 30); do
  curl -fs http://127.0.0.1:8000/api/health >/dev/null && break
  sleep 1
done
curl -fs http://127.0.0.1:8000/api/health && echo
REMOTE
