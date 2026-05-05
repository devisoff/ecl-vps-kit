#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
need_root

TARGET_DIR="/opt/reshala-shaper"
REPO_URL="https://github.com/DonMatteoVPN/Reshala-Remnawave-Bedolaga.git"

log "Установка модуля ограничения скорости клиентов"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git curl ca-certificates python3 python3-pip clang llvm libelf-dev make iproute2 bpftool linux-tools-common || true

if [[ -d "${TARGET_DIR}/.git" ]]; then
  log "Обновляю ${TARGET_DIR}"
  git -C "${TARGET_DIR}" pull --ff-only || true
else
  rm -rf "${TARGET_DIR}"
  git clone --depth 1 "${REPO_URL}" "${TARGET_DIR}"
fi

cat > /usr/local/bin/ecl-shaper <<'CONF'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/reshala-shaper
if [[ -f modules/local/traffic_limiter.sh ]]; then
  bash modules/local/traffic_limiter.sh "$@"
elif [[ -f traffic_limiter.sh ]]; then
  bash traffic_limiter.sh "$@"
else
  echo "Не найден модуль traffic_limiter.sh в /opt/reshala-shaper" >&2
  exit 1
fi
CONF
chmod +x /usr/local/bin/ecl-shaper

ok "Модуль установлен. Запуск ограничения скорости: ecl-shaper"
if confirm "Запустить ecl-shaper сейчас?"; then
  ecl-shaper
fi
