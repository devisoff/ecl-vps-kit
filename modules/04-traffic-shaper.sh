#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
trace_errors "04-traffic-shaper.sh"
need_root

TARGET_DIR="/opt/reshala-shaper"
REPO_URL="https://github.com/DonMatteoVPN/Reshala-Remnawave-Bedolaga.git"

install_bpf_tools_best_effort() {
  if command -v bpftool >/dev/null 2>&1; then
    return 0
  fi

  apt_get install -y bpftool >/dev/null 2>&1 \
    || apt_get install -y "linux-tools-$(uname -r)" linux-tools-common linux-tools-generic >/dev/null 2>&1 \
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
  log "Проверяю зависимости шейпера"
  ensure_packages \
    git curl ca-certificates python3 python3-pip \
    clang llvm libelf-dev libbpf-dev make iproute2 jq bc kmod
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

quick_create_rule() {
  local rule_id="${1:-1}"
  local mode="${2:-1}"
  local ports="${3:-443}"
  local down="${4:-5}"
  local up="${5:-5}"
  local iface="${6:-}"
  local pspeed="0.1"
  local burst="100"
  local win="10"
  local pen="60"

  if [[ -z "${iface}" ]]; then
    if [[ -f "${TL_CONFIG_DIR}/ebpf_config.conf" ]]; then
      # shellcheck source=/dev/null
      source "${TL_CONFIG_DIR}/ebpf_config.conf"
      iface="${IFACE:-}"
    fi
  fi
  if [[ -z "${iface}" ]]; then
    iface="$(ip route | awk '/^default /{print $5; exit}')"
  fi
  if [[ -z "${iface}" ]]; then
    iface="$(ip -br link | awk '$1 != "lo" && $1 !~ /^docker/ && $1 !~ /^br-/ && $1 !~ /^veth/ {print $1; exit}')"
  fi
  if [[ -z "${iface}" ]]; then
    echo "Не удалось определить сетевой интерфейс" >&2
    return 1
  fi

  _tl_ensure_ebpf_deps || return 1

  if ! systemctl is-active --quiet "${TL_SERVICE_NAME}" || [[ ! -d "${TL_BPF_PIN_DIR}/maps" ]]; then
    _tl_cleanup_old_system || true
    _tl_compile_bpf || return 1
    mkdir -p "${TL_CONFIG_DIR}"
    cat > "${TL_CONFIG_DIR}/ebpf_config.conf" <<EOF_CONF
IFACE="${iface}"
EOF_CONF
    systemctl unmask "${TL_SERVICE_NAME}" >/dev/null 2>&1 || true
    _tl_generate_ebpf_service_file > "${TL_SERVICE_PATH}" || return 1
    systemctl daemon-reload
    systemctl enable "${TL_SERVICE_NAME}" >/dev/null 2>&1 || true
    systemctl restart "${TL_SERVICE_NAME}" || return 1

    local timeout=10
    while [[ ! -d "${TL_BPF_PIN_DIR}/maps" && ${timeout} -gt 0 ]]; do
      sleep 1
      timeout=$((timeout - 1))
    done
    if [[ ! -d "${TL_BPF_PIN_DIR}/maps" ]]; then
      echo "eBPF движок не запустился. Проверь: journalctl -u ${TL_SERVICE_NAME}" >&2
      return 1
    fi
  fi

  python3 "${TL_CTRL_PY_PATH}" \
    --pin-dir "${TL_BPF_PIN_DIR}/maps" \
    --rules-file "${TL_CONFIG_DIR}/rules.json" \
    set \
    --rule-id "${rule_id}" \
    --mode "${mode}" \
    --ports "${ports}" \
    --down "${down}" \
    --up "${up}" \
    --pen "${pspeed}" \
    --burst "${burst}" \
    --win "${win}" \
    --pen-sec "${pen}"
}

action="${1:-menu}"
case "${action}" in
  menu)
    call_first_available show_traffic_limiter_menu
    ;;
  create)
    call_first_available _tl_apply_limit_ebpf_wizard _tl_apply_limit_wizard
    ;;
  quick-create)
    shift
    quick_create_rule "$@"
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
    echo "Использование: ecl-shaper [menu|create|quick-create|rules|stats|logs|restart]" >&2
    exit 2
    ;;
esac

exit 0
WRAP
  chmod +x /usr/local/bin/ecl-shaper
  mark_installed "shaper"
}

prompt_int_range() {
  local prompt="$1" min="$2" max="$3" default_value="$4" value
  while true; do
    value="$(prompt_default "${prompt}" "${default_value}")"
    if [[ "${value}" =~ ^[0-9]+$ ]] && (( value >= min && value <= max )); then
      printf '%s' "${value}"
      return 0
    fi
    warn "Введи число от ${min} до ${max}."
  done
}

prompt_float_positive() {
  local prompt="$1" default_value="$2" value
  while true; do
    value="$(prompt_default "${prompt}" "${default_value}")"
    if [[ "${value}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      printf '%s' "${value}"
      return 0
    fi
    warn "Введи число, например 5 или 5.5."
  done
}

prompt_ports_csv() {
  local prompt="$1" default_value="$2" value
  while true; do
    value="$(prompt_default "${prompt}" "${default_value}")"
    value="$(printf '%s' "${value}" | tr -d ' ')"
    if [[ "${value}" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
      printf '%s' "${value}"
      return 0
    fi
    warn "Введи порт или список портов через запятую, например 443 или 443,80,8080."
  done
}

read_menu_choice() {
  local prompt="${1:-Выбери пункт}"
  local default_value="${2:-}"
  local value
  if [[ -n "${default_value}" ]]; then
    printf "%s [%s]\n> " "${prompt}" "${default_value}" >&2
  else
    printf "%s\n> " "${prompt}" >&2
  fi
  IFS= read -r value || true
  value="$(printf '%s' "${value}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  printf '%s' "${value:-${default_value}}"
}

quick_default_rule() {
  local iface_default
  clear
  printf "${C_CYAN}Шейпер трафика — авто-правило${C_RESET}\n\n"
  printf "Применяю значения по умолчанию:\n"
  printf "  правило    : 1\n"
  printf "  режим      : 1, статический\n"
  printf "  порт       : 443\n"
  printf "  скачивание : 5 МБ/с\n"
  printf "  загрузка   : 5 МБ/с\n\n"

  iface_default="$(default_iface || true)"
  [[ -z "${iface_default}" ]] && iface_default="eth0"

  ecl-shaper quick-create 1 1 443 5 5 "${iface_default}"
  ok "Авто-правило применено: #1, режим 1, порт 443, DL/UL 5/5 МБ/с"
}

quick_rule_wizard() {
  local rule_id iface_default iface mode ports down up
  clear
  printf "${C_CYAN}Шейпер трафика — быстрое правило${C_RESET}\n\n"
  printf "Enter применяет значения по умолчанию:\n"
  printf '%s\n' "- правило: 1"
  printf '%s\n' "- режим: 1, статический"
  printf '%s\n' "- порт: 443"
  printf '%s\n' "- скачивание: 5 МБ/с"
  printf '%s\n\n' "- загрузка: 5 МБ/с"

  rule_id="$(prompt_int_range "Номер правила" 0 31 1)"
  iface_default="$(default_iface || true)"
  [[ -z "${iface_default}" ]] && iface_default="eth0"
  iface="$(prompt_default "Интерфейс" "${iface_default}")"
  mode="$(prompt_int_range "Режим: 1=статический, 2=динамический, 3=общий" 1 3 1)"
  ports="$(prompt_ports_csv "Порты" "443")"
  down="$(prompt_float_positive "Скачивание DL, МБ/с" "5")"
  up="$(prompt_float_positive "Загрузка UL, МБ/с" "5")"

  printf "\n"
  printf "Правило #%s: режим %s, интерфейс %s, порты %s, DL/UL %s/%s МБ/с\n" \
    "${rule_id}" "${mode}" "${iface}" "${ports}" "${down}" "${up}"

  if confirm_yes "Применить правило?"; then
    ecl-shaper quick-create "${rule_id}" "${mode}" "${ports}" "${down}" "${up}" "${iface}"
    ok "Правило применено"
  else
    warn "Отменено"
  fi
}

show_shaper_menu() {
  while true; do
    clear
    printf "${C_CYAN}Шейпер трафика${C_RESET}\n"
    printf "0) Авто-правило: #1, режим 1, порт 443, 5/5 МБ/с\n"
    printf "1) Создать / изменить правило вручную\n"
    printf "2) Просмотреть текущие правила\n"
    printf "3) Статистика\n"
    printf "4) Полное меню Reshala Shaper\n"
    printf "5) Лог сервиса\n"
    printf "6) Перезапустить движок\n"
    printf "b) Назад\n\n"
    choice="$(read_menu_choice "Выбери пункт" "1")"
    case "${choice}" in
      0) quick_default_rule || true; pause ;;
      1) ecl-shaper create || true; pause ;;
      2) ecl-shaper rules || true; pause ;;
      3) ecl-shaper stats || true; pause ;;
      4) ecl-shaper menu || true; pause ;;
      5) ecl-shaper logs || true; pause ;;
      6) ecl-shaper restart || true; pause ;;
      b|B|б|Б|q|Q|й|Й) return 0 ;;
      *) warn "Неверный выбор"; sleep 1 ;;
    esac
  done
}

ensure_repo
ok "Шейпер установлен. Быстрый запуск: ecl-shaper"
show_shaper_menu
