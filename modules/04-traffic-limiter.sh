#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
need_root

TARGET_DIR="/opt/reshala-shaper"
REPO_URL="https://github.com/DonMatteoVPN/Reshala-Remnawave-Bedolaga.git"

ensure_repo() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y git curl ca-certificates python3 python3-pip clang llvm libelf-dev libbpf-dev make iproute2 bpftool jq bc kmod || true

  if [[ -d "${TARGET_DIR}/.git" ]]; then
    log "Обновляю шейпер в ${TARGET_DIR}"
    git -C "${TARGET_DIR}" pull --ff-only || true
  else
    log "Скачиваю модуль шейпера"
    rm -rf "${TARGET_DIR}"
    git clone --depth 1 "${REPO_URL}" "${TARGET_DIR}"
  fi

  cat > /usr/local/bin/ecl-shaper <<'WRAP'
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="/opt/reshala-shaper"
if [[ ! -f "${SCRIPT_DIR}/modules/local/traffic_limiter.sh" ]]; then
  echo "Шейпер не найден. Открой ecl → пункт 4 и установи модуль." >&2
  exit 1
fi

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/modules/local/traffic_limiter.sh"

action="${1:-menu}"
case "${action}" in
  menu)
    show_traffic_limiter_menu
    ;;
  create)
    _tl_apply_limit_ebpf_wizard
    ;;
  rules)
    _tl_list_rules
    ;;
  stats)
    _tl_show_status
    ;;
  log|logs)
    _tl_view_service_log
    ;;
  restart)
    _tl_restart_ebpf_engine
    ;;
  *)
    echo "Использование: ecl-shaper [menu|create|rules|stats|logs|restart]" >&2
    exit 2
    ;;
esac
WRAP
  chmod +x /usr/local/bin/ecl-shaper
}

show_shaper_menu() {
  while true; do
    clear
    printf "${C_CYAN}Шейпер трафика${C_RESET}\n"
    printf "1) Создать / изменить правило\n"
    printf "2) Просмотреть текущие правила\n"
    printf "3) Статистика\n"
    printf "4) Полное меню Reshala Shaper\n"
    printf "5) Лог сервиса\n"
    printf "6) Перезапустить движок\n"
    printf "b) Назад\n\n"
    choice="$(ask_line "Выбери пункт")"
    case "${choice}" in
      1) ecl-shaper create; pause ;;
      2) ecl-shaper rules; pause ;;
      3) ecl-shaper stats; pause ;;
      4) ecl-shaper menu ;;
      5) ecl-shaper logs; pause ;;
      6) ecl-shaper restart; pause ;;
      b|B|0) return 0 ;;
      *) warn "Неверный выбор"; sleep 1 ;;
    esac
  done
}

ensure_repo
ok "Шейпер установлен. Быстрый запуск: ecl-shaper"
show_shaper_menu
