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

# Базовые пакеты, которые стабильно ставятся на Ubuntu 24.04.
apt-get install -y \
  ca-certificates curl wget tar gzip coreutils sed grep gawk procps findutils \
  iproute2 dnsutils net-tools jq lsb-release software-properties-common \
  ufw fail2ban iptables git python3 python3-pip make clang llvm libelf-dev \
  libbpf-dev kmod bc

# bpftool на Ubuntu может быть виртуальным пакетом без кандидата. Не валим установку,
# а пробуем поставить через linux-tools. Шейпер при запуске дополнительно проверит зависимости.
if ! command -v bpftool >/dev/null 2>&1; then
  apt-get install -y bpftool >/dev/null 2>&1 \
    || apt-get install -y "linux-tools-$(uname -r)" linux-tools-common linux-tools-generic >/dev/null 2>&1 \
    || warn "bpftool не установлен автоматически. Шейпер попробует установить его отдельно."
fi

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

mark_installed "system-update"
ok "Система обновлена, базовые пакеты установлены"
