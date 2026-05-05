#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/core/common.sh"
need_root

bar() {
  local pct="${1:-0}" width="${2:-10}" filled empty
  pct="${pct%.*}"
  [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  filled=$((pct * width / 100))
  empty=$((width - filled))
  printf '['
  printf '%*s' "$filled" '' | tr ' ' '█'
  printf '%*s' "$empty" '' | tr ' ' '░'
  printf ']'
}

cpu_usage() {
  local a b idle total idle2 total2 diff_idle diff_total usage
  read -r _ a b c idle rest < /proc/stat
  total=$((a+b+c+idle))
  sleep 0.2
  read -r _ a b c idle2 rest < /proc/stat
  total2=$((a+b+c+idle2))
  diff_idle=$((idle2-idle))
  diff_total=$((total2-total))
  if (( diff_total > 0 )); then
    usage=$(( (100 * (diff_total - diff_idle)) / diff_total ))
  else
    usage=0
  fi
  echo "$usage"
}

public_ip() {
  curl -4 -fsS --max-time 2 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}' || echo "n/a"
}

os_pretty() {
  . /etc/os-release 2>/dev/null || true
  printf '%s' "${PRETTY_NAME:-Unknown Linux}"
}

docker_status() {
  if ! cmd_exists docker; then echo "Docker не установлен"; return; fi
  if service_active docker; then echo "Docker активен"; else echo "Docker не активен"; fi
}

remnanode_status() {
  if ! cmd_exists docker; then echo "не проверено"; return; fi
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'remnanode'; then
    echo "Remnawave Node работает"
  else
    echo "Remnawave Node не найден"
  fi
}

show_dashboard() {
  clear || true
  local os uptime virt ip cpu_model cpu_pct mem_total mem_used mem_pct disk_total disk_used disk_pct
  os="$(os_pretty)"
  uptime="$(uptime -p 2>/dev/null | sed 's/up //')"
  virt="$(systemd-detect-virt 2>/dev/null || echo unknown)"
  ip="$(public_ip)"
  cpu_model="$(lscpu 2>/dev/null | awk -F: '/Model name|Имя модели/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')"
  cpu_model="${cpu_model:-Unknown CPU}"
  cpu_pct="$(cpu_usage)"
  mem_total="$(free -m | awk '/Mem:/ {print $2}')"
  mem_used="$(free -m | awk '/Mem:/ {print $3}')"
  mem_pct=$(( mem_total > 0 ? 100 * mem_used / mem_total : 0 ))
  disk_total="$(df -h / | awk 'NR==2 {print $2}')"
  disk_used="$(df -h / | awk 'NR==2 {print $3}')"
  disk_pct="$(df / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"

  printf "%b\n" "${C_BLUE}╔════════════════════════════════════════════════════════════╗${C_RESET}"
  printf "%b\n" "${C_BLUE}║${C_RESET} ${C_BOLD}${APP_NAME}${C_RESET}"
  printf "%b\n" "${C_BLUE}╚════════════════════════════════════════════════════════════╝${C_RESET}"
  echo
  printf "%b\n" "${C_BLUE}┌─[ СИСТЕМА ]${C_RESET}"
  printf "%-22s : %b\n" "ОС / Ядро" "${C_GREEN}${os} ($(uname -r))${C_RESET}"
  printf "%-22s : %s\n" "Аптайм" "${uptime:-n/a}"
  printf "%-22s : %s\n" "Виртуалка" "$virt"
  printf "%-22s : %b\n" "IP Адрес" "${C_RED}${ip}${C_RESET}"
  echo
  printf "%b\n" "${C_BLUE}┌─[ ЖЕЛЕЗО ]${C_RESET}"
  printf "%-22s : %b\n" "CPU Модель" "${C_GREEN}${cpu_model}${C_RESET}"
  printf "%-22s : %s %s%%\n" "Загрузка CPU" "$(bar "$cpu_pct")" "$cpu_pct"
  printf "%-22s : %s %s%% (%sM/%sM)\n" "Память RAM" "$(bar "$mem_pct")" "$mem_pct" "$mem_used" "$mem_total"
  printf "%-22s : %s %s%% (%s/%s)\n" "Диск /" "$(bar "$disk_pct")" "$disk_pct" "$disk_used" "$disk_total"
  echo
  printf "%b\n" "${C_BLUE}┌─[ STATUS ]${C_RESET}"
  printf "%-22s : %b\n" "Docker" "${C_GREEN}$(docker_status)${C_RESET}"
  printf "%-22s : %b\n" "Remnawave" "${C_GREEN}$(remnanode_status)${C_RESET}"
  echo
}

run_module() {
  local module="$1"
  bash "$SCRIPT_DIR/modules/$module"
}

while true; do
  show_dashboard
  printf "%b\n" "${C_CYAN}1)${C_RESET} Установить сетевые настройки Ubuntu"
  printf "%b\n" "${C_CYAN}2)${C_RESET} Установить защиту: UFW + TrafficGuard-auto + Fail2Ban"
  printf "%b\n" "${C_CYAN}3)${C_RESET} Установить ноду Remnawave"
  printf "%b\n" "${C_CYAN}4)${C_RESET} Ограничение скорости клиентов"
  printf "%b\n" "${C_CYAN}5)${C_RESET} Установить z4r запрет"
  printf "%b\n" "${C_CYAN}6)${C_RESET} Проверки / статус"
  printf "%b\n" "${C_CYAN}7)${C_RESET} Перезапустить ноду Remnawave"
  printf "%b\n" "${C_CYAN}8)${C_RESET} Установить всё по очереди"
  printf "%b\n" "${C_CYAN}0)${C_RESET} Выход"
  echo
  read -r -p "Выбери пункт: " choice || exit 0

  case "$choice" in
    1) run_module "01-network.sh" ;;
    2) run_module "02-security.sh" ;;
    3) run_module "03-remnawave-node.sh" ;;
    4) run_module "04-traffic-limiter.sh" ;;
    5) run_module "05-z4r.sh" ;;
    6) run_module "06-checks.sh" ;;
    7) run_module "07-restart-node.sh" ;;
    8)
      run_module "01-network.sh"
      run_module "02-security.sh"
      run_module "03-remnawave-node.sh"
      run_module "04-traffic-limiter.sh"
      run_module "05-z4r.sh"
      ;;
    0|q|Q) exit 0 ;;
    *) warn "Нет такого пункта"; sleep 1 ;;
  esac
  pause
 done
