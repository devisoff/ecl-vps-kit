#!/usr/bin/env bash
# Common helpers for ECL VPS Kit modules.

set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
STATE_DIR="${STATE_DIR:-/etc/ecl-vps-kit}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/settings.env}"

C_RESET='\033[0m'
C_BLUE='\033[1;34m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_CYAN='\033[1;36m'
C_GRAY='\033[0;37m'
C_WHITE='\033[1;37m'

log() { printf "${C_BLUE}[ECL]${C_RESET} %s\n" "$*"; }
ok() { printf "${C_GREEN}[OK]${C_RESET} %s\n" "$*"; }
warn() { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$*"; }
fail() { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$*" >&2; }

need_root() {
  if [[ ${EUID} -ne 0 ]]; then
    fail "Запусти от root: sudo ecl"
    exit 1
  fi
}

pause() {
  printf "\n"
  read -r -p "Нажми Enter для возврата в меню..." _ || true
}

ask_line() {
  local prompt="$1"
  local value
  printf "%s\n> " "${prompt}"
  IFS= read -r value || true
  printf '%s' "${value}"
}

confirm_yes() {
  local prompt="${1:-Продолжить?}"
  local answer
  answer="$(ask_line "${prompt} [Y/n]")"
  answer="$(printf '%s' "${answer}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "${answer}" || "${answer}" =~ ^[YyДд]$ ]]
}

confirm_no() {
  local prompt="${1:-Продолжить?}"
  local answer
  answer="$(ask_line "${prompt} [y/N]")"
  answer="$(printf '%s' "${answer}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ "${answer}" =~ ^[YyДд]$ ]]
}

prompt_required() {
  local prompt="$1"
  local value=""
  while [[ -z "${value}" ]]; do
    value="$(ask_line "${prompt}")"
    value="$(printf '%s' "${value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  done
  printf '%s' "${value}"
}

prompt_default() {
  local prompt="$1"
  local default_value="$2"
  local value
  value="$(ask_line "${prompt} [${default_value}]")"
  value="$(printf '%s' "${value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  printf '%s' "${value:-$default_value}"
}

prompt_default_optional() {
  local prompt="$1"
  local default_value="${2:-}"
  local value
  if [[ -n "${default_value}" ]]; then
    value="$(ask_line "${prompt} [${default_value}]")"
  else
    value="$(ask_line "${prompt}")"
  fi
  value="$(printf '%s' "${value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  printf '%s' "${value:-$default_value}"
}

is_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

prompt_port() {
  local prompt="$1"
  local default_value="${2:-}"
  local value
  while true; do
    if [[ -n "${default_value}" ]]; then
      value="$(prompt_default "${prompt}" "${default_value}")"
    else
      value="$(prompt_required "${prompt}")"
    fi
    if is_port "${value}"; then
      printf '%s' "${value}"
      return 0
    fi
    warn "Некорректный порт. Введи число от 1 до 65535."
  done
}

is_ipv4_or_cidr() {
  local value="$1"
  [[ "${value}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]] || return 1

  local ip mask old_ifs part
  ip="${value%/*}"
  mask=""
  [[ "${value}" == */* ]] && mask="${value#*/}"
  if [[ -n "${mask}" && ( ! "${mask}" =~ ^[0-9]+$ || "${mask}" -lt 0 || "${mask}" -gt 32 ) ]]; then
    return 1
  fi
  old_ifs="${IFS}"
  IFS='.'
  read -r -a parts <<< "${ip}"
  IFS="${old_ifs}"
  [[ ${#parts[@]} -eq 4 ]] || return 1
  for part in "${parts[@]}"; do
    [[ "${part}" =~ ^[0-9]+$ ]] || return 1
    (( part >= 0 && part <= 255 )) || return 1
  done
}

strip_domain_input() {
  local value="$1"
  value="${value#http://}"
  value="${value#https://}"
  value="${value%%/*}"
  value="${value%%:*}"
  printf '%s' "${value}"
}

is_domain_name() {
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ ]] && [[ "$1" == *.* ]]
}

resolve_domain_ipv4() {
  local host="$1"
  getent ahostsv4 "${host}" 2>/dev/null | awk '{print $1}' | sort -u | head -n 1
}

human_bytes() {
  local bytes="${1:-0}"
  awk -v b="${bytes}" 'BEGIN {
    split("B KB MB GB TB PB", u, " "); i=1;
    while (b>=1024 && i<6) { b/=1024; i++ }
    if (i==1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
  }'
}

save_setting() {
  local key="$1"
  local value="$2"
  mkdir -p "${STATE_DIR}"
  touch "${STATE_FILE}"
  chmod 600 "${STATE_FILE}"
  if grep -qE "^${key}=" "${STATE_FILE}"; then
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "${STATE_FILE}"
  else
    printf '%s="%s"\n' "${key}" "${value}" >> "${STATE_FILE}"
  fi
}

load_settings() {
  if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${STATE_FILE}"
  fi
}

run_module() {
  local module="$1"
  need_root
  if [[ ! -f "${APP_DIR}/modules/${module}" ]]; then
    fail "Модуль не найден: ${APP_DIR}/modules/${module}"
    exit 1
  fi
  bash "${APP_DIR}/modules/${module}"
}

service_is_active() {
  local service="$1"
  systemctl is-active --quiet "${service}" 2>/dev/null
}

docker_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    return 1
  fi
}

default_iface() {
  ip route 2>/dev/null | awk '/^default /{print $5; exit}'
}
