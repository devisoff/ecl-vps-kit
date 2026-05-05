#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
need_root

if [[ ! -d /opt/remnanode ]]; then
  fail "Папка /opt/remnanode не найдена. Сначала установи ноду."
  exit 1
fi

cd /opt/remnanode
compose_cmd="$(docker_compose_cmd)"

log "Перезапускаю Remnawave Node"
${compose_cmd} pull
${compose_cmd} down
${compose_cmd} up -d
${compose_cmd} logs -f
