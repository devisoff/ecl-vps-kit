#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
trace_errors "03-remnawave-node.sh"
need_root
load_settings

log "Установка Remnawave Node"

ensure_packages curl ca-certificates

if ! command -v docker >/dev/null 2>&1; then
  log "Устанавливаю Docker"
  if ! fetch_and_run "https://get.docker.com" "установщик Docker" sh; then
    fail "Не удалось установить Docker. Прерываю установку ноды."
    exit 1
  fi
else
  ok "Docker уже установлен: $(docker --version)"
fi

systemctl enable docker >/dev/null 2>&1 || warn "Не удалось включить автозапуск docker."
systemctl start docker || { fail "Docker не запустился."; exit 1; }

mkdir -p /opt/remnanode
cd /opt/remnanode

node_port="$(prompt_port "Порт Remnawave Node" "${NODE_PORT:-2222}")"
secret_key="$(prompt_default "SECRET_KEY для Remnawave Node" "${SECRET_KEY:-change_me}")"

save_setting "NODE_PORT" "${node_port}"
save_setting "SECRET_KEY" "${secret_key}"

cat > /opt/remnanode/.env <<CONF
NODE_PORT=${node_port}
SECRET_KEY=${secret_key}
CONF
chmod 600 /opt/remnanode/.env

if [[ -f /opt/remnanode/docker-compose.yml ]]; then
  if confirm_yes "docker-compose.yml уже существует. Перезаписать шаблоном?"; then
    overwrite_compose="yes"
  else
    overwrite_compose="no"
  fi
else
  overwrite_compose="yes"
fi

if [[ "${overwrite_compose}" == "yes" ]]; then
  cat > /opt/remnanode/docker-compose.yml <<'CONF'
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
CONF
fi

if ! compose_cmd="$(require_compose)"; then
  exit 1
fi
${compose_cmd} pull
${compose_cmd} up -d

mark_installed "remnanode"
ok "Remnawave Node установлен/запущен"
${compose_cmd} ps || true
