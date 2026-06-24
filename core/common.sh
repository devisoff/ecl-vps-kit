#!/usr/bin/env bash
# Common helpers for ECL VPS Kit modules.
#
# Sourced by menu.sh and every module. Provides logging, prompts, a robust
# apt wrapper that survives the dpkg-lock race on fresh VPS boots, an ERR
# trap that prints *where* a module died, and safe wrappers around the
# fragile bits (sysctl on container kernels, docker compose, curl|bash).

set -Eeuo pipefail

ECL_VERSION="2.0"

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
STATE_DIR="${STATE_DIR:-/etc/ecl-vps-kit}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/settings.env}"

# Seconds apt is allowed to wait for the dpkg lock before we intervene.
APT_LOCK_WAIT="${APT_LOCK_WAIT:-600}"

# --- colors --------------------------------------------------------------
# Disable colors when output is not a terminal or NO_COLOR is set, so logs
# captured to files / piped through `tee` stay readable.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET='\033[0m'; C_BLUE='\033[1;34m'; C_GREEN='\033[1;32m'
  C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_CYAN='\033[1;36m'
  C_GRAY='\033[0;37m'; C_WHITE='\033[1;37m'
else
  C_RESET=''; C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''
  C_CYAN=''; C_GRAY=''; C_WHITE=''
fi

log()  { printf "${C_BLUE}[ECL]${C_RESET} %s\n"   "$*"; }
ok()   { printf "${C_GREEN}[OK]${C_RESET} %s\n"    "$*"; }
warn() { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$*"; }
fail() { printf "${C_RED}[ERROR]${C_RESET} %s\n"   "$*" >&2; }

# --- error tracing -------------------------------------------------------
# Call once near the top of a module: `trace_errors`. When any command
# trips `set -e`, this prints the module, line, command and exit code so a
# crash is never "for unclear reasons" again.
_ecl_err_trap() {
  local rc="$1" line="$2" cmd="$3"
  fail "Сбой в ${ECL_MODULE:-модуле}: строка ${line}, команда «${cmd}», код ${rc}"
}

trace_errors() {
  ECL_MODULE="${1:-$(basename -- "${BASH_SOURCE[1]:-module}")}"
  trap '_ecl_err_trap "$?" "${LINENO}" "${BASH_COMMAND}"' ERR
}

need_root() {
  if [[ ${EUID} -ne 0 ]]; then
    fail "Запусти от root: sudo ecl"
    exit 1
  fi
}

pause() {
  printf "\n" >&2
  printf "Нажми Enter для возврата в меню..." >&2
  read -r _ || true
}

# --- apt: lock-safe wrapper ---------------------------------------------
# The #1 cause of crashes on a freshly booted VPS: apt-daily /
# unattended-upgrades holds /var/lib/dpkg/lock-frontend, so the first
# apt-get returns code 100 and `set -e` kills the module. We wait for the
# lock, pass apt's native DPkg::Lock::Timeout, retry transient failures,
# and only as a last resort stop the background auto-update units.

_apt_lock_files=(
  /var/lib/dpkg/lock-frontend
  /var/lib/dpkg/lock
  /var/lib/apt/lists/lock
  /var/cache/apt/archives/lock
)

_apt_lock_busy() {
  # Returns 0 if any apt/dpkg lock is currently held by another process.
  command -v fuser >/dev/null 2>&1 || return 1   # can't tell → assume free
  local lk
  for lk in "${_apt_lock_files[@]}"; do
    [[ -e "${lk}" ]] || continue
    if fuser "${lk}" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

apt_wait_for_lock() {
  local waited=0 step=3 announced=0
  while _apt_lock_busy; do
    if (( announced == 0 )); then
      warn "Пакетный менеджер занят (вероятно, авто-обновление при загрузке). Жду dpkg-блокировку..."
      announced=1
    fi
    if (( waited >= APT_LOCK_WAIT )); then
      warn "Блокировка держится дольше ${APT_LOCK_WAIT}s — останавливаю фоновые авто-обновления."
      systemctl stop unattended-upgrades.service apt-daily.service \
        apt-daily-upgrade.service apt-daily.timer apt-daily-upgrade.timer \
        >/dev/null 2>&1 || true
      sleep "${step}"
      return 0
    fi
    sleep "${step}"
    waited=$(( waited + step ))
  done
  (( announced == 1 )) && ok "dpkg-блокировка освобождена, продолжаю."
  return 0
}

apt_get() {
  # Drop-in replacement for `apt-get` used across modules.
  export DEBIAN_FRONTEND=noninteractive
  local attempt=1 max=3 rc=0
  while (( attempt <= max )); do
    apt_wait_for_lock
    if apt-get \
        -o DPkg::Lock::Timeout="${APT_LOCK_WAIT}" \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        "$@"; then
      return 0
    fi
    rc=$?
    warn "apt-get $* → код ${rc} (попытка ${attempt}/${max}). Повторяю."
    sleep 5
    attempt=$(( attempt + 1 ))
  done
  fail "apt-get не справился за ${max} попыток: $*"
  return "${rc}"
}

# Run `apt-get update` at most once per ~10 minutes (shared via a stamp
# file) so the combined install (menu item 8) does not update three times.
apt_update_once() {
  local stamp="${STATE_DIR}/.apt-updated" ttl=10
  if [[ -f "${stamp}" && -n "$(find "${stamp}" -mmin "-${ttl}" 2>/dev/null)" ]]; then
    return 0
  fi
  apt_get update -y || return $?
  mkdir -p "${STATE_DIR}"
  : > "${stamp}"
}

# Install packages idempotently. Usage: ensure_packages curl wget ufw ...
ensure_packages() {
  (( $# > 0 )) || return 0
  apt_update_once
  apt_get install -y "$@"
}

# --- safe remote installer ----------------------------------------------
# Replaces `curl ... | bash`: downloads to a temp file with retries, checks
# it is non-empty, then runs it — so a network blip or SIGPIPE produces a
# clear error instead of a mysterious pipefail abort.
fetch_and_run() {
  local url="$1" desc="${2:-внешний скрипт}" interp="${3:-bash}"
  local tmp rc
  tmp="$(mktemp)" || { fail "mktemp не сработал"; return 1; }
  log "Скачиваю ${desc}"
  if ! curl -fsSL --retry 3 --retry-delay 2 --max-time 120 "${url}" -o "${tmp}"; then
    fail "Не удалось скачать ${desc} (${url})."
    rm -f "${tmp}"
    return 1
  fi
  if [[ ! -s "${tmp}" ]]; then
    fail "${desc}: получен пустой файл, запуск отменён."
    rm -f "${tmp}"
    return 1
  fi
  "${interp}" "${tmp}"
  rc=$?
  rm -f "${tmp}"
  (( rc == 0 )) || fail "${desc} завершился с кодом ${rc}."
  return "${rc}"
}

# --- prompts -------------------------------------------------------------
ask_line() {
  local prompt="$1"
  local value
  # Prompt goes to stderr so command substitutions capture only user input.
  printf "%s\n> " "${prompt}" >&2
  IFS= read -r value || true
  printf '%s' "${value}"
}

_trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

confirm_yes() {
  local answer
  answer="$(_trim "$(ask_line "${1:-Продолжить?} [Y/n]")")"
  [[ -z "${answer}" || "${answer}" =~ ^[YyДд]$ ]]
}

confirm_no() {
  local answer
  answer="$(_trim "$(ask_line "${1:-Продолжить?} [y/N]")")"
  [[ "${answer}" =~ ^[YyДд]$ ]]
}

prompt_required() {
  local value=""
  while [[ -z "${value}" ]]; do
    value="$(_trim "$(ask_line "$1")")"
  done
  printf '%s' "${value}"
}

prompt_default() {
  local value
  value="$(_trim "$(ask_line "$1 [$2]")")"
  printf '%s' "${value:-$2}"
}

prompt_default_optional() {
  local prompt="$1" default_value="${2:-}" value
  if [[ -n "${default_value}" ]]; then
    value="$(_trim "$(ask_line "${prompt} [${default_value}]")")"
  else
    value="$(_trim "$(ask_line "${prompt}")")"
  fi
  printf '%s' "${value:-$default_value}"
}

is_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 )); }

prompt_port() {
  local prompt="$1" default_value="${2:-}" value
  while true; do
    if [[ -n "${default_value}" ]]; then
      value="$(prompt_default "${prompt}" "${default_value}")"
    else
      value="$(prompt_required "${prompt}")"
    fi
    if is_port "${value}"; then printf '%s' "${value}"; return 0; fi
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
  getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u | head -n 1
}

human_bytes() {
  awk -v b="${1:-0}" 'BEGIN {
    split("B KB MB GB TB PB", u, " "); i=1;
    while (b>=1024 && i<6) { b/=1024; i++ }
    if (i==1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
  }'
}

# --- settings persistence ------------------------------------------------
save_setting() {
  local key="$1" value="$2"
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

# --- module running ------------------------------------------------------
run_module() {
  local module="$1" status=0
  need_root
  if [[ ! -f "${APP_DIR}/modules/${module}" ]]; then
    fail "Модуль не найден: ${APP_DIR}/modules/${module}"
    return 0
  fi
  # Run in a child bash so a module crash never takes down the menu.
  if bash "${APP_DIR}/modules/${module}"; then
    status=0
  else
    status=$?
    warn "Модуль ${module} завершился с ошибкой (код ${status}). Возвращаюсь в меню."
  fi
  return 0
}

mark_installed() {
  mkdir -p "${STATE_DIR}"
  touch "${STATE_DIR}/$1.installed"
}

is_marked_installed() { [[ -f "${STATE_DIR}/$1.installed" ]]; }

service_is_active() { systemctl is-active --quiet "$1" 2>/dev/null; }

docker_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    return 1
  fi
}

# Resolve docker compose or print a clear error. Use as:
#   if ! compose="$(require_compose)"; then exit 1; fi
require_compose() {
  local cmd
  if cmd="$(docker_compose_cmd)"; then
    printf '%s' "${cmd}"
    return 0
  fi
  fail "Docker Compose не найден. Сначала установи ноду (пункт 3)."
  return 1
}

default_iface() {
  ip route 2>/dev/null | awk '/^default /{print $5; exit}'
}

# --- sysctl: container-safe ---------------------------------------------
# `sysctl --system` returns non-zero if the kernel rejects a key (common on
# LXC/OpenVZ and old kernels: no nf_conntrack, no bbr). Under `set -e` that
# aborts the whole module. This applies what it can and never fails.
apply_sysctl_safe() {
  if sysctl --system >/dev/null 2>&1; then
    ok "Параметры sysctl применены."
    return 0
  fi
  warn "Ядро приняло не все sysctl-параметры — применяю по одному (норма для LXC/OpenVZ)."
  local f
  for f in /etc/sysctl.d/*.conf /etc/sysctl.conf; do
    [[ -f "${f}" ]] || continue
    sysctl -p "${f}" >/dev/null 2>&1 || true
  done
  return 0
}

# True if the kernel can do BBR congestion control.
supports_bbr() {
  modprobe tcp_bbr >/dev/null 2>&1 || true
  grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null
}

# True if nf_conntrack is available (tunables exposed under /proc).
supports_conntrack() {
  modprobe nf_conntrack >/dev/null 2>&1 || true
  [[ -e /proc/sys/net/netfilter/nf_conntrack_max ]]
}
