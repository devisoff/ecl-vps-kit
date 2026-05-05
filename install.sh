#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="ecl-vps-kit"
APP_DIR="/opt/ecl-vps-kit"
BIN_NAME="ecl"
REPO_OWNER="devisoff"
REPO_NAME="ecl-vps-kit"
BRANCH="main"
ARCHIVE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${BRANCH}.tar.gz"

log() { printf '\033[1;34m[ECL]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[ECL]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ECL]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ECL]\033[0m %s\n' "$*" >&2; }

need_root() {
  if [[ ${EUID} -ne 0 ]]; then
    err "Запусти установку от root: sudo bash install.sh"
    exit 1
  fi
}

install_base_deps() {
  export DEBIAN_FRONTEND=noninteractive
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y ca-certificates curl wget tar coreutils sed grep gawk procps findutils
  fi
}

install_from_local_tree() {
  local src_dir="$1"
  log "Копирую локальные файлы в ${APP_DIR}"
  rm -rf "${APP_DIR}"
  mkdir -p "${APP_DIR}"
  cp -a "${src_dir}/." "${APP_DIR}/"
}

install_from_github() {
  local tmp_dir archive_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT

  log "Скачиваю ${REPO_OWNER}/${REPO_NAME}@${BRANCH}"
  curl -fsSL "${ARCHIVE_URL}" -o "${tmp_dir}/${APP_NAME}.tar.gz"
  tar -xzf "${tmp_dir}/${APP_NAME}.tar.gz" -C "${tmp_dir}"
  archive_dir="$(find "${tmp_dir}" -maxdepth 1 -type d -name "${REPO_NAME}-*" | head -n 1)"

  if [[ -z "${archive_dir}" || ! -d "${archive_dir}" ]]; then
    err "Не удалось распаковать архив репозитория"
    exit 1
  fi

  rm -rf "${APP_DIR}"
  mkdir -p "${APP_DIR}"
  cp -a "${archive_dir}/." "${APP_DIR}/"
}

create_command() {
  log "Создаю команду ${BIN_NAME}"
  cat > "/usr/local/bin/${BIN_NAME}" <<EOF2
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ \${EUID} -ne 0 ]]; then
  exec sudo bash "${APP_DIR}/menu.sh" "\$@"
fi
exec bash "${APP_DIR}/menu.sh" "\$@"
EOF2
  chmod +x "/usr/local/bin/${BIN_NAME}"

  # Backward-compatible alias for earlier test builds.
  cat > "/usr/local/bin/vpskit" <<EOF2
#!/usr/bin/env bash
exec /usr/local/bin/${BIN_NAME} "\$@"
EOF2
  chmod +x "/usr/local/bin/vpskit"
}

fix_permissions() {
  find "${APP_DIR}" -type f -name "*.sh" -exec chmod +x {} \;
  chmod +x "${APP_DIR}/menu.sh" "${APP_DIR}/install.sh"
}

main() {
  need_root
  install_base_deps

  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

  if [[ -f "${script_dir}/menu.sh" && -d "${script_dir}/modules" && -d "${script_dir}/core" ]]; then
    install_from_local_tree "${script_dir}"
  else
    install_from_github
  fi

  fix_permissions
  create_command

  ok "Установка завершена. Запуск меню: ecl"
}

main "$@"
