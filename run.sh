#!/usr/bin/env bash
# Запуск всего проекта одной командой: бэкенд + сайт + приложение на телефоне.
#
#   ./run.sh            всё: сервер, сайт в браузере, приложение на подключённом телефоне
#   ./run.sh --sim      то же, но приложение в симуляторе iOS / эмуляторе Android
#   ./run.sh --web      только сервер и сайт (телефон не трогаем)
#
# Остановка: Ctrl+C (или q в flutter run) — гасит и сервер, и приложение.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PORT="${DIARY_PORT:-8000}"
URL="http://localhost:$PORT"
MODE=phone
case "${1:-}" in
  --web) MODE=web ;;
  --sim) MODE=sim ;;
  "") ;;
  *) echo "Использование: ./run.sh [--web | --sim]" >&2; exit 2 ;;
esac

say() { printf '\033[1;33m▸ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

command -v uv >/dev/null || die "Не найден uv: https://docs.astral.sh/uv/"
command -v flutter >/dev/null || die "Не найден flutter"
if lsof -ti ":$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  die "Порт $PORT уже занят. Остановите прошлый запуск или задайте DIARY_PORT=8001 ./run.sh"
fi

# 1. Устройство: телефон или симулятор/эмулятор (не браузер и не Mac).
DEVICE=""
DEVICE_PLATFORM=""
if [[ $MODE != web ]]; then
  say "Ищу устройство…"
  read -r DEVICE DEVICE_PLATFORM < <(flutter devices --machine 2>/dev/null | WANT_EMULATOR=$([[ $MODE == sim ]] && echo 1 || echo 0) python3 -c '
import json, os, sys
try:
    devices = json.load(sys.stdin)
except ValueError:
    devices = []
want_emulator = os.environ["WANT_EMULATOR"] == "1"
for d in devices:
    platform = d.get("targetPlatform", "")
    if platform.startswith(("ios", "android")) and bool(d.get("emulator")) == want_emulator:
        print(d["id"], platform); break
' || true) || true
  if [[ -z "$DEVICE" ]]; then
    if [[ $MODE == sim ]]; then
      say "Симулятор не запущен (open -a Simulator) — запускаю только сервер и сайт"
    else
      say "Телефон не найден — запускаю только сервер и сайт (для симулятора: ./run.sh --sim)"
    fi
  fi
fi

# 2. Адрес API для приложения. Сервер открывается в сеть только для настоящего
#    телефона; симулятор iOS и эмулятор Android ходят на этот Mac напрямую.
HOST=127.0.0.1
API_URL=""
if [[ -n "$DEVICE" ]]; then
  if [[ $MODE == sim ]]; then
    # Эмулятор Android видит Mac по адресу 10.0.2.2, симулятор iOS — по localhost.
    [[ $DEVICE_PLATFORM == android* ]] && API_URL="http://10.0.2.2:$PORT" || API_URL="http://localhost:$PORT"
  else
    LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
    if [[ -z "$LAN_IP" ]]; then
      say "Не удалось узнать IP Мака в локальной сети — телефон пропускаю"
      DEVICE=""
    else
      HOST=0.0.0.0
      API_URL="http://$LAN_IP:$PORT"
    fi
  fi
fi

# 3. Сайт: пересобираем, только если менялся код Flutter.
WEB_INDEX="$ROOT/app/build/web/index.html"
if [[ ! -f "$WEB_INDEX" ]] || [[ -n "$(find "$ROOT/app/lib" "$ROOT/app/web" "$ROOT/app/assets" \
      "$ROOT/app/pubspec.yaml" -newer "$WEB_INDEX" -print -quit)" ]]; then
  say "Собираю веб-версию (код изменился)…"
  (cd "$ROOT/app" && flutter build web --release --no-web-resources-cdn)
else
  say "Веб-версия актуальна"
fi

# 4. Бэкенд (он же раздаёт сайт).
say "Запускаю сервер на $HOST:$PORT"
(cd "$ROOT/backend" && DIARY_HOST="$HOST" DIARY_PORT="$PORT" exec uv run diary) &
SERVER_PID=$!

cleanup() {
  trap - EXIT INT TERM
  if kill -0 "$SERVER_PID" 2>/dev/null; then
    say "Останавливаю сервер"
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

for _ in $(seq 1 60); do
  curl -fs "$URL/api/health" >/dev/null 2>&1 && break
  kill -0 "$SERVER_PID" 2>/dev/null || die "Сервер не запустился — смотрите вывод выше"
  sleep 0.5
done
curl -fs "$URL/api/health" >/dev/null || die "Сервер не отвечает на $URL"

say "Сайт: $URL   (вход: demo / demo12345)"
[[ -z "${NO_OPEN:-}" ]] && { open -a "Google Chrome" "$URL" 2>/dev/null || open "$URL" 2>/dev/null || true; }

# 5. Приложение — на переднем плане.
if [[ -n "$DEVICE" ]]; then
  say "Запускаю приложение на устройстве $DEVICE, API: $API_URL"
  say "В приложении: r — перезагрузить, q — выйти (сервер тоже остановится)"
  (cd "$ROOT/app" && flutter run -d "$DEVICE" --dart-define=API_BASE_URL="$API_URL") || true
else
  say "Сервер работает. Ctrl+C — остановить."
  wait "$SERVER_PID"
fi
