#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
need_root

log "Установка z4r"

if ! confirm "Запустить внешний скрипт z4r?"; then
  warn "Отменено"
  exit 0
fi

require_command curl curl
cd /root
curl -fsSLO https://raw.githubusercontent.com/IndeecFOX/z4r/4/z4r
sh z4r

ok "z4r выполнен"
