#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
need_root

TARGET_DIR="/opt/reshala-shaper"
REPO_URL="https://github.com/DonMatteoVPN/Reshala-Remnawave-Bedolaga.git"

install_bpf_tools_best_effort() {
  if command -v bpftool >/dev/null 2>&1; then
    return 0
  fi

  apt-get install -y bpftool >/dev/null 2>&1 \
    || apt-get install -y "linux-tools-$(uname -r)" linux-tools-common linux-tools-generic >/dev/null 2>&1 \
    || true

  if ! command -v bpftool >/dev/null 2>&1; then
    for candidate in \
      "/usr/lib/linux-tools/$(uname -r)/bpftool" \
      "/usr/lib/linux-tools-generic/bpftool" \
      /usr/lib/linux-tools-*/bpftool; do
      if [[ -x "${candidate}" ]]; then
        ln -sf "${candidate}" /usr/local/bin/bpftool 2>/dev/null || true
        break
      fi
    done
  fi
}

ensure_repo() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y git curl ca-certificates python3 python3-pip clang llvm libelf-dev libbpf-dev make iproute2 jq bc kmod || true
  install_bpf_tools_best_effort

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
# Thin wrapper around Reshala traffic limiter functions.
# It never exits the parent ecl menu: errors are returned to the caller.
set +e

SCRIPT_DIR="/opt/reshala-shaper"
export SCRIPT_DIR

if [[ ! -f "${SCRIPT_DIR}/modules/local/traffic_limiter.sh" ]]; then
  echo "Шейпер не найден. Открой ecl → пункт 4 и установи модуль." >&2
  exit 1
fi

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/modules/local/traffic_limiter.sh"

call_first_available() {
  local fn
  for fn in "$@"; do
    if declare -F "${fn}" >/dev/null 2>&1; then
      "${fn}"
      return 0
    fi
  done
  echo "Функция шейпера не найдена. Попробуй полное меню: ecl-shaper menu" >&2
  return 1
}

action="${1:-menu}"
case "${action}" in
  menu)
    call_first_available show_traffic_limiter_menu
    ;;
  create)
    call_first_available _tl_apply_limit_ebpf_wizard _tl_apply_limit_wizard
    ;;
  rules)
    call_first_available _tl_list_rules _tl_show_status
    ;;
  stats)
    call_first_available _tl_show_status
    ;;
  log|logs)
    call_first_available _tl_view_service_log
    ;;
  restart)
    call_first_available _tl_restart_ebpf_engine _tl_restart_service
    ;;
  *)
    echo "Использование: ecl-shaper [menu|create|rules|stats|logs|restart]" >&2
    exit 2
    ;;
esac

exit 0
WRAP
  chmod +x /usr/local/bin/ecl-shaper
  mark_installed "shaper"
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
    choice="$(printf '%s' "${choice}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "${choice}" in
      1) ecl-shaper create || true; pause ;;
      2) ecl-shaper rules || true; pause ;;
      3) ecl-shaper stats || true; pause ;;
      4) ecl-shaper menu || true ;;
      5) ecl-shaper logs || true; pause ;;
      6) ecl-shaper restart || true; pause ;;
      b|B|0) return 0 ;;
      *) warn "Неверный выбор"; sleep 1 ;;
    esac
  done
}

ensure_repo
ok "Шейпер установлен. Быстрый запуск: ecl-shaper"
show_shaper_menu
