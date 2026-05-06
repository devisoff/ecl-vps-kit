#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
need_root

log "Установка z4r"

if ! confirm_yes "Запустить внешний скрипт z4r?"; then
  warn "Отменено"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get install -y curl ca-certificates

mkdir -p /opt/z4r
curl -fsSL https://raw.githubusercontent.com/IndeecFOX/z4r/4/z4r -o /opt/z4r/z4r
chmod +x /opt/z4r/z4r

cat > /usr/local/bin/ecl-z4r <<'WRAP'
#!/usr/bin/env bash
exec sh /opt/z4r/z4r "$@"
WRAP
chmod +x /usr/local/bin/ecl-z4r

sh /opt/z4r/z4r
touch "${STATE_DIR}/z4r.installed"

ok "z4r выполнен. Быстрый запуск: ecl-z4r"
