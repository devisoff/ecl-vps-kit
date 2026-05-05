#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=core/common.sh
source "${APP_DIR}/core/common.sh"

bar() {
  local used="$1" total="$2" width=12
  local filled=0
  if [[ "${total}" =~ ^[0-9]+$ && "${total}" -gt 0 ]]; then
    filled=$(( used * width / total ))
  fi
  (( filled > width )) && filled=${width}
  printf '['
  for ((i=0; i<width; i++)); do
    if (( i < filled )); then printf '█'; else printf '░'; fi
  done
  printf ']'
}

get_public_ip() {
  curl -fsS --max-time 2 https://api.ipify.org 2>/dev/null || echo "не определён"
}

system_info() {
  local os kernel uptime virt ip cpu cpu_load ram_total ram_used disk_total disk_used docker_status node_status
  os="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-Unknown}")"
  kernel="$(uname -r)"
  uptime="$(uptime -p 2>/dev/null | sed 's/^up //' || echo '-')"
  virt="$(systemd-detect-virt 2>/dev/null || echo 'none')"
  ip="$(get_public_ip)"
  cpu="$(awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null || echo '-')"
  cpu_load="$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || echo '-')"
  ram_total="$(free -m | awk '/Mem:/{print $2}')"
  ram_used="$(free -m | awk '/Mem:/{print $3}')"
  disk_total="$(df -m / | awk 'NR==2{print $2}')"
  disk_used="$(df -m / | awk 'NR==2{print $3}')"

  if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker 2>/dev/null; then
    docker_status="активен"
  else
    docker_status="не установлен/не активен"
  fi

  if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -Eq '^remnanode$'; then
    node_status="запущена"
  elif [[ -d /opt/remnanode ]]; then
    node_status="установлена, но не запущена"
  else
    node_status="не установлена"
  fi

  clear
  printf "${C_CYAN}┌─[ СИСТЕМА ]${C_RESET}\n"
  printf "│ ОС / Ядро        : ${C_GREEN}%s${C_RESET} (%s)\n" "${os}" "${kernel}"
  printf "│ Аптайм           : ${C_GREEN}%s${C_RESET}\n" "${uptime}"
  printf "│ Виртуализация    : ${C_GREEN}%s${C_RESET}\n" "${virt}"
  printf "│ IP адрес         : ${C_RED}%s${C_RESET}\n" "${ip}"
  printf "│ CPU              : ${C_GREEN}%s${C_RESET}\n" "${cpu:0:58}"
  printf "│ Load average     : ${C_GREEN}%s${C_RESET}\n" "${cpu_load}"
  printf "│ RAM              : "
  bar "${ram_used}" "${ram_total}"
  printf " ${C_GREEN}%sM/%sM${C_RESET}\n" "${ram_used}" "${ram_total}"
  printf "│ Disk /           : "
  bar "${disk_used}" "${disk_total}"
  printf " ${C_GREEN}%sM/%sM${C_RESET}\n" "${disk_used}" "${disk_total}"
  printf "│ Docker           : ${C_GREEN}%s${C_RESET}\n" "${docker_status}"
  printf "│ Remnawave Node   : ${C_GREEN}%s${C_RESET}\n" "${node_status}"
  printf "└────────────────────────────────────────────────────────────\n\n"
}

show_menu() {
  printf "${C_CYAN}ECL VPS Kit${C_RESET}\n"
  printf "1) Сетевые настройки Ubuntu\n"
  printf "2) Защита: UFW + TrafficGuard-auto + Fail2Ban\n"
  printf "3) Установка Remnawave Node\n"
  printf "4) Ограничение скорости клиентов\n"
  printf "5) Установка z4r\n"
  printf "6) Проверки состояния\n"
  printf "7) Перезапустить Remnawave Node\n"
  printf "8) Установить всё по порядку\n"
  printf "0) Выход\n\n"
}

main() {
  need_root
  while true; do
    system_info
    show_menu
    read -r -p "Выбери пункт: " choice || true
    case "${choice}" in
      1) run_module "01-network.sh"; pause ;;
      2) run_module "02-security.sh"; pause ;;
      3) run_module "03-remnawave-node.sh"; pause ;;
      4) run_module "04-traffic-limiter.sh"; pause ;;
      5) run_module "05-z4r.sh"; pause ;;
      6) run_module "06-checks.sh"; pause ;;
      7) run_module "07-restart-node.sh"; pause ;;
      8)
        run_module "01-network.sh"
        run_module "02-security.sh"
        run_module "03-remnawave-node.sh"
        run_module "04-traffic-limiter.sh"
        run_module "05-z4r.sh"
        pause
        ;;
      0) exit 0 ;;
      *) warn "Неверный выбор"; sleep 1 ;;
    esac
  done
}

main "$@"
