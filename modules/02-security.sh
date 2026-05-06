#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
# shellcheck source=../core/common.sh
source "${APP_DIR}/core/common.sh"
need_root
load_settings

log "Настройка защиты: UFW + TrafficGuard-auto + Fail2Ban"

if ! confirm_yes "Модуль сбросит текущие правила UFW и применит новые. Продолжить?"; then
  warn "Отменено"
  exit 0
fi

node_port="$(prompt_port "Порт ноды, который нужно открыть только для панели" "${NODE_PORT:-2222}")"

while true; do
  default_panel="${PANEL_HOST:-${PANEL_IP:-}}"
  panel_input="$(prompt_default_optional "IP/CIDR или домен панели" "${default_panel}")"
  panel_input="$(strip_domain_input "${panel_input}")"

  if is_ipv4_or_cidr "${panel_input}"; then
    panel_ip="${panel_input}"
    panel_host="${panel_input}"
    break
  fi

  if is_domain_name "${panel_input}"; then
    log "Проверяю A-запись домена: ${panel_input}"
    resolved_ip="$(resolve_domain_ipv4 "${panel_input}")"
    if [[ -n "${resolved_ip}" ]]; then
      ok "Найден IP: ${resolved_ip}"
      if confirm_yes "Использовать ${resolved_ip} для правила UFW?"; then
        panel_ip="${resolved_ip}"
        panel_host="${panel_input}"
        break
      fi
    else
      warn "Не удалось получить IPv4 для домена ${panel_input}"
    fi
  else
    warn "Введите IPv4, CIDR или домен. Пример: 1.2.3.4, 1.2.3.0/24, panel.example.com"
  fi
done

ssh_ports="$(prompt_default "SSH-порты для Fail2Ban" "${SSH_PORTS:-22,2222}")"

save_setting "NODE_PORT" "${node_port}"
save_setting "PANEL_HOST" "${panel_host}"
save_setting "PANEL_IP" "${panel_ip}"
save_setting "SSH_PORTS" "${ssh_ports}"

export DEBIAN_FRONTEND=noninteractive
apt-get install -y ufw curl ca-certificates fail2ban iptables dnsutils

log "Отключаю IPv6 для UFW"
sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw

log "Сбрасываю UFW"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

log "Добавляю правила UFW"
ufw allow OpenSSH || true

# Защита от случайной блокировки SSH: дополнительно открываем порты из sshd -T.
if command -v sshd >/dev/null 2>&1; then
  while read -r detected_port; do
    if is_port "${detected_port}"; then
      ufw allow "${detected_port}/tcp" || true
    fi
  done < <(sshd -T 2>/dev/null | awk '/^port /{print $2}' | sort -u)
fi

ufw allow 443/tcp
ufw allow from "${panel_ip}" to any port "${node_port}" proto tcp

log "Разрешаю ICMP echo-request"
if ! grep -q -- "-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT" /etc/ufw/before.rules; then
  cp /etc/ufw/before.rules "/etc/ufw/before.rules.bak.$(date +%F-%H%M%S)"
  sed -i '/# ok icmp codes for INPUT/a -A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT' /etc/ufw/before.rules
fi

ufw --force enable
ufw reload

log "Устанавливаю TrafficGuard-auto"
if confirm_yes "Запустить установщик TrafficGuard-auto из внешнего репозитория?"; then
  curl -fsSL https://raw.githubusercontent.com/DonMatteoVPN/TrafficGuard-auto/refs/heads/main/install-trafficguard.sh | bash
else
  warn "TrafficGuard-auto пропущен"
fi

log "Настраиваю Fail2Ban"
systemctl enable fail2ban
systemctl start fail2ban

cat > /etc/fail2ban/jail.local <<CONF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd
banaction = iptables-multiport

[sshd]
enabled = true
port = ${ssh_ports}
logpath = %(sshd_log)s
CONF

systemctl restart fail2ban

mark_installed "security"
ok "Защита настроена"
ufw status numbered || true
fail2ban-client status sshd || true
