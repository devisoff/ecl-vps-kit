#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
trace_errors "06-checks.sh"
need_root

status_text() {
  if "$@" >/dev/null 2>&1; then
    printf "${C_GREEN}работает${C_RESET}"
  else
    printf "${C_RED}не работает${C_RESET}"
  fi
}

installed_text() {
  if "$@" >/dev/null 2>&1; then
    printf "${C_GREEN}установлено${C_RESET}"
  else
    printf "${C_RED}не установлено${C_RESET}"
  fi
}

network_applied() {
  [[ -f /etc/sysctl.d/99-vpn-node.conf ]] && systemctl is-enabled --quiet conntrack-tune.service 2>/dev/null
}

ufw_active() { ufw status 2>/dev/null | grep -q "Status: active"; }
trafficguard_active() {
  command -v rknpidor >/dev/null 2>&1 || [[ -f /var/log/iptables-scanners-aggregate.csv ]]
}
fail2ban_active() { systemctl is-active --quiet fail2ban 2>/dev/null; }
remnanode_installed() { [[ -d /opt/remnanode ]] && [[ -f /opt/remnanode/docker-compose.yml ]]; }
z4r_installed() { command -v ecl-z4r >/dev/null 2>&1 || [[ -f "${STATE_DIR}/z4r.installed" ]]; }
shaper_installed() { command -v ecl-shaper >/dev/null 2>&1 || [[ -d /opt/reshala-shaper ]]; }

trafficguard_stats() {
  clear
  printf "${C_CYAN}Статистика защиты${C_RESET}\n\n"

  if command -v rknpidor >/dev/null 2>&1; then
    rknpidor || true
    printf "\n"
  fi

  LOG="/var/log/iptables-scanners-aggregate.csv"
  if [[ -f "${LOG}" ]]; then
    total="$(awk -F',' '{sum+=$3} END {print sum+0}' "${LOG}")"
    uniq_ips="$(awk -F',' '{print $2}' "${LOG}" | sort -u | wc -l)"
    printf "TrafficGuard: атак: ${C_GREEN}%s${C_RESET}, уникальных IP: ${C_GREEN}%s${C_RESET}\n" "${total}" "${uniq_ips}"
  else
    printf "TrafficGuard: ${C_YELLOW}лог не найден${C_RESET}\n"
  fi

  if command -v fail2ban-client >/dev/null 2>&1; then
    printf "\nFail2Ban sshd:\n"
    fail2ban-client status sshd 2>/dev/null | awk '/Currently banned|Total banned|Jail list|Status/{print}' || true
  else
    printf "Fail2Ban: ${C_RED}не установлен${C_RESET}\n"
  fi
}

show_summary() {
  clear
  printf "${C_CYAN}Проверки состояния${C_RESET}\n\n"
  printf "Сетевые настройки: "
  if network_applied; then printf "${C_GREEN}применены${C_RESET}\n"; else printf "${C_RED}не применены${C_RESET}\n"; fi

  printf "Защита: UFW "
  if ufw_active; then printf "${C_GREEN}работает${C_RESET}"; else printf "${C_RED}не работает${C_RESET}"; fi
  printf ", TrafficGuard-auto "
  if trafficguard_active; then printf "${C_GREEN}работает/установлен${C_RESET}"; else printf "${C_RED}не найден${C_RESET}"; fi
  printf ", Fail2Ban "
  if fail2ban_active; then printf "${C_GREEN}работает${C_RESET}\n"; else printf "${C_RED}не работает${C_RESET}\n"; fi

  printf "Remnawave Node: "
  if remnanode_installed; then printf "${C_GREEN}установлена${C_RESET}\n"; else printf "${C_RED}не установлена${C_RESET}\n"; fi

  printf "z4r: "
  if z4r_installed; then printf "${C_GREEN}установлен${C_RESET}\n"; else printf "${C_RED}не установлен${C_RESET}\n"; fi

  printf "Шейпер: "
  if shaper_installed; then
    if systemctl is-active --quiet reshala-traffic-limiter.service 2>/dev/null; then
      printf "${C_GREEN}установлен и работает${C_RESET}\n"
    else
      printf "${C_YELLOW}установлен, сервис не активен${C_RESET}\n"
    fi
  else
    printf "${C_RED}не установлен${C_RESET}\n"
  fi

  printf "\n"
  printf "1) Статистика защиты\n"
  printf "2) Открыть z4r\n"
  printf "3) Открыть Шейпер\n"
  printf "b) Назад\n\n"
}

while true; do
  show_summary
  choice="$(ask_line "Выбери пункт")"
  choice="$(printf '%s' "${choice}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  case "${choice}" in
    1) trafficguard_stats; pause ;;
    2)
      if command -v ecl-z4r >/dev/null 2>&1; then
        ecl-z4r
      else
        warn "z4r не установлен. Запускаю установку."
        bash "${APP_DIR}/modules/05-z4r.sh"
      fi
      pause
      ;;
    3)
      bash "${APP_DIR}/modules/04-traffic-shaper.sh"
      ;;
    b|B|q|Q|й|Й|0) exit 0 ;;
    *) warn "Неверный выбор"; sleep 1 ;;
  esac
done
