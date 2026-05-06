#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
need_root

log "Применяю сетевые настройки Ubuntu"

cat > /etc/modules-load.d/nf_conntrack.conf <<'CONF'
nf_conntrack
CONF

cat > /etc/modprobe.d/nf_conntrack.conf <<'CONF'
options nf_conntrack hashsize=262144
CONF

modprobe nf_conntrack || warn "Не удалось загрузить nf_conntrack сразу. Сервис применит настройку после перезагрузки."

cat > /etc/sysctl.d/99-vpn-node.conf <<'CONF'
# Queue discipline + congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# NAT / conntrack
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 21600
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 120
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120

# Ephemeral ports
# Service ports used on these nodes are below 10000: 22, 443, 2222, 8443, 9999
net.ipv4.ip_local_port_range = 10000 65535

# Socket buffers
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 262144
net.core.wmem_default = 262144

# TCP autotuning buffers
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# Network queues
net.core.netdev_max_backlog = 65536
net.core.somaxconn = 65535

# TCP optimizations
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0

# TCP keepalive
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# Busy VPS tuning
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 8000

# System file descriptor limit
fs.file-max = 2097152
CONF

sysctl --system

cat > /etc/systemd/system/conntrack-tune.service <<'CONF'
[Unit]
Description=Apply conntrack tuning
After=systemd-modules-load.service network-pre.target ufw.service docker.service
Wants=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/sbin/modprobe nf_conntrack
ExecStart=/usr/sbin/sysctl -w net.netfilter.nf_conntrack_max=1048576
ExecStart=/usr/sbin/sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=21600
ExecStart=/usr/sbin/sysctl -w net.netfilter.nf_conntrack_tcp_timeout_close_wait=60
ExecStart=/usr/sbin/sysctl -w net.netfilter.nf_conntrack_tcp_timeout_fin_wait=120
ExecStart=/usr/sbin/sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=120
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
CONF

systemctl daemon-reload
systemctl enable conntrack-tune.service
systemctl restart conntrack-tune.service

cat > /etc/security/limits.d/99-vpn-node.conf <<'CONF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
CONF

mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/99-nofile.conf <<'CONF'
[Manager]
DefaultLimitNOFILE=1048576
CONF

systemctl daemon-reexec

mark_installed "network"
ok "Сетевые настройки применены"
warn "Для полного применения лимитов файловых дескрипторов может потребоваться новый SSH-сеанс или перезагрузка."
