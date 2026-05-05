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

require_command() {
  local cmd="$1"
  local pkg="${2:-$1}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log "Устанавливаю пакет: ${pkg}"
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkg}"
  fi
}

confirm() {
  local prompt="${1:-Продолжить?}"
  local answer
  read -r -p "${prompt} [y/N]: " answer || true
  [[ "${answer}" =~ ^[YyДд]$ ]]
}

prompt_required() {
  local prompt="$1"
  local value=""
  while [[ -z "${value}" ]]; do
    read -r -p "${prompt}: " value || true
    value="$(printf '%s' "${value}" | xargs)"
  done
  printf '%s' "${value}"
}

prompt_default() {
  local prompt="$1"
  local default_value="$2"
  local value
  read -r -p "${prompt} [${default_value}]: " value || true
  value="$(printf '%s' "${value}" | xargs)"
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
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]
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
