#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
need_root

section() { printf "\n${C_CYAN}=== %s ===${C_RESET}\n" "$1"; }
show_cmd() { printf "${C_YELLOW}$ %s${C_RESET}\n" "$*"; "$@" 2>&1 || true; }

section "conntrack"
show_cmd cat /proc/sys/net/netfilter/nf_conntrack_count
show_cmd cat /proc/sys/net/netfilter/nf_conntrack_max
show_cmd cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established
show_cmd systemctl status conntrack-tune.service --no-pager

section "TCP"
show_cmd sysctl net.ipv4.tcp_congestion_control
show_cmd sysctl net.core.default_qdisc

section "ports"
show_cmd sysctl net.ipv4.ip_local_port_range

section "queues"
show_cmd sysctl net.core.somaxconn
show_cmd sysctl net.core.netdev_max_backlog

section "buffers"
show_cmd sysctl net.core.rmem_max
show_cmd sysctl net.core.wmem_max

section "limits"
show_cmd bash -lc 'ulimit -n'
show_cmd systemctl show --property=DefaultLimitNOFILE
show_cmd cat /proc/sys/fs/file-max

section "UFW"
show_cmd ufw status numbered

section "Fail2Ban"
show_cmd fail2ban-client status sshd

section "Docker"
show_cmd docker --version
show_cmd systemctl status docker --no-pager

section "Remnawave Node"
if [[ -d /opt/remnanode ]]; then
  cd /opt/remnanode
  if compose_cmd="$(docker_compose_cmd)"; then
    show_cmd ${compose_cmd} ps
  else
    warn "docker compose не найден"
  fi
else
  warn "/opt/remnanode не найден"
fi

section "TrafficGuard"
if command -v rknpidor >/dev/null 2>&1; then
  show_cmd rknpidor
else
  warn "Команда rknpidor не найдена"
fi

LOG="/var/log/iptables-scanners-aggregate.csv"
if [[ -f "${LOG}" ]]; then
  printf "\n📊 TrafficGuard статистика\n"
  printf "======================================\n"
  TOTAL="$(awk -F',' '{sum+=$3} END {print sum+0}' "${LOG}")"
  if [[ "${TOTAL}" -eq 0 ]]; then
    echo "Нет атак 🎉"
  else
    echo "Общее количество атак: ${TOTAL}"
    echo -n "Уникальных IP: "
    awk -F',' '{print $2}' "${LOG}" | sort -u | wc -l
  fi
  printf "======================================\n"
else
  warn "Лог TrafficGuard не найден: ${LOG}"
fi
