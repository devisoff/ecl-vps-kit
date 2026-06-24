#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
trace_errors "05-z4r.sh"
need_root

log "Установка z4r"

if ! confirm_yes "Запустить внешний скрипт z4r?"; then
  warn "Отменено"
  exit 0
fi

ensure_packages curl ca-certificates

mkdir -p /opt/z4r
if ! curl -fsSL --retry 3 --retry-delay 2 --max-time 120 \
     https://raw.githubusercontent.com/IndeecFOX/z4r/4/z4r -o /opt/z4r/z4r; then
  fail "Не удалось скачать z4r."
  exit 1
fi
if [[ ! -s /opt/z4r/z4r ]]; then
  fail "z4r: получен пустой файл."
  exit 1
fi
chmod +x /opt/z4r/z4r

cat > /usr/local/bin/ecl-z4r <<'WRAP'
#!/usr/bin/env bash
exec sh /opt/z4r/z4r "$@"
WRAP
chmod +x /usr/local/bin/ecl-z4r

sh /opt/z4r/z4r
touch "${STATE_DIR}/z4r.installed"

ok "z4r выполнен. Быстрый запуск: ecl-z4r"
