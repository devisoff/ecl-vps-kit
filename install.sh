#!/usr/bin/env bash
set -Eeuo pipefail

# После публикации на GitHub замени эти 3 значения под свой репозиторий.
REPO_OWNER="CHANGE_ME"
REPO_NAME="vps-node-kit"
BRANCH="main"

INSTALL_DIR="/opt/vps-node-kit"
BIN_PATH="/usr/local/bin/ecl"
LEGACY_BIN_PATH="/usr/local/bin/vpskit"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"

C_RESET='\033[0m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_RED='\033[31m'; C_CYAN='\033[36m'
info(){ printf "%b\n" "${C_CYAN}[i]${C_RESET} $*"; }
ok(){ printf "%b\n" "${C_GREEN}[✓]${C_RESET} $*"; }
warn(){ printf "%b\n" "${C_YELLOW}[!]${C_RESET} $*"; }
err(){ printf "%b\n" "${C_RED}[x]${C_RESET} $*" >&2; }

if [[ ${EUID} -ne 0 ]]; then
  err "Запусти от root: sudo bash install.sh"
  exit 1
fi

mkdir -p "$INSTALL_DIR"

copy_local_repo() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$here/menu.sh" && -d "$here/modules" && -d "$here/core" ]]; then
    info "Локальная установка из: $here"
    rm -rf "$INSTALL_DIR"/*
    cp -a "$here/menu.sh" "$here/core" "$here/modules" "$here/configs" "$INSTALL_DIR"/
    [[ -f "$here/README.md" ]] && cp -a "$here/README.md" "$INSTALL_DIR"/
    return 0
  fi
  return 1
}

download_remote_repo() {
  if [[ "$REPO_OWNER" == "CHANGE_ME" ]]; then
    err "В install.sh нужно заменить REPO_OWNER=\"CHANGE_ME\" на твой GitHub username/org."
    err "Или запускай локально из папки репозитория: sudo bash install.sh"
    exit 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y curl ca-certificates
  fi

  info "Скачиваю файлы из $RAW_BASE"
  rm -rf "$INSTALL_DIR"/*
  mkdir -p "$INSTALL_DIR/core" "$INSTALL_DIR/modules" "$INSTALL_DIR/configs"

  local files=(
    "menu.sh"
    "core/common.sh"
    "modules/01-network.sh"
    "modules/02-security.sh"
    "modules/03-remnawave-node.sh"
    "modules/04-traffic-limiter.sh"
    "modules/05-z4r.sh"
    "modules/06-checks.sh"
    "modules/07-restart-node.sh"
    "configs/README.md"
    "README.md"
  )

  local f
  for f in "${files[@]}"; do
    mkdir -p "$INSTALL_DIR/$(dirname "$f")"
    curl -fsSL "$RAW_BASE/$f" -o "$INSTALL_DIR/$f"
  done
}

if ! copy_local_repo; then
  download_remote_repo
fi

chmod +x "$INSTALL_DIR/menu.sh" "$INSTALL_DIR"/modules/*.sh

cat > "$BIN_PATH" <<EOF2
#!/usr/bin/env bash
exec bash "$INSTALL_DIR/menu.sh" "\$@"
EOF2
chmod +x "$BIN_PATH"

cat > "$LEGACY_BIN_PATH" <<EOF2
#!/usr/bin/env bash
exec bash "$INSTALL_DIR/menu.sh" "\$@"
EOF2
chmod +x "$LEGACY_BIN_PATH"

ok "Установлено в $INSTALL_DIR"
ok "Команда меню: ecl"
info "Старая команда vpskit тоже оставлена как алиас."

echo
read -r -p "Открыть меню сейчас? [Y/n] " answer || true
answer="${answer:-y}"
if [[ "$answer" =~ ^[YyДд]$ ]]; then
  exec "$BIN_PATH"
fi
