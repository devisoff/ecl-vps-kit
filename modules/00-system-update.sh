#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
need_root

log "Обновление Ubuntu и установка базовых пакетов"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  ca-certificates curl wget tar gzip coreutils sed grep gawk procps findutils \
  iproute2 dnsutils net-tools jq lsb-release software-properties-common \
  ufw fail2ban iptables git python3 python3-pip make clang llvm libelf-dev \
  libbpf-dev bpftool kmod bc

ok "Система обновлена, базовые пакеты установлены"
