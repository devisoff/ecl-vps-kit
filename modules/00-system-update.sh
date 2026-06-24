#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
trace_errors "00-system-update.sh"
need_root

log "Обновление Ubuntu и установка базовых пакетов для модулей 1-2-3"

# apt_update_once / apt_get handle the dpkg-lock race on fresh boots,
# pass DPkg::Lock::Timeout and retry transient failures.
apt_update_once
apt_get upgrade -y

# Только базовый минимум, который нужен для:
# 1) сетевых настроек Ubuntu,
# 2) защиты UFW + TrafficGuard-auto + Fail2Ban,
# 3) установки Docker / Remnawave Node.
# Шейпер и z4r ставят свои зависимости отдельно при запуске соответствующих пунктов.
apt_get install -y \
  ca-certificates \
  curl \
  wget \
  tar \
  gzip \
  procps \
  psmisc \
  iproute2 \
  kmod \
  ufw \
  fail2ban \
  iptables

mark_installed "system-update"
ok "Система обновлена, базовые пакеты для 1-2-3 установлены"
