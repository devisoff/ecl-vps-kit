#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="ecl-vps-kit"
APP_DIR="/opt/ecl-vps-kit"
BIN_NAME="ecl"
LEGACY_BIN_NAME="vpskit"
REPO_OWNER="devisoff"
REPO_NAME="ecl-vps-kit"
BRANCH="main"
ARCHIVE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${BRANCH}.tar.gz"
TMP_DIR=""

log() { printf '\033[1;34m[ECL]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[ECL]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ECL]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ECL]\033[0m %s\n' "$*" >&2; }

cleanup() {
  if [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

need_root() {
  if [[ ${EUID} -ne 0 ]]; then
    err "Запусти установку от root: sudo bash install.sh"
    exit 1
  fi
}

need_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    err "Не найдена команда: ${cmd}"
    err "Установи базовые пакеты: apt update && apt install -y wget tar gzip ca-certificates"
    exit 1
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
  local archive_dir=""
  TMP_DIR="$(mktemp -d)"

  need_cmd wget
  need_cmd tar
  need_cmd gzip

  log "Скачиваю ${REPO_OWNER}/${REPO_NAME}@${BRANCH}"
  wget -q -O "${TMP_DIR}/${APP_NAME}.tar.gz" "${ARCHIVE_URL}"
  tar -xzf "${TMP_DIR}/${APP_NAME}.tar.gz" -C "${TMP_DIR}"
  archive_dir="$(find "${TMP_DIR}" -maxdepth 1 -type d -name "${REPO_NAME}-*" | head -n 1)"

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

  cat > "/usr/local/bin/${LEGACY_BIN_NAME}" <<EOF2
#!/usr/bin/env bash
exec /usr/local/bin/${BIN_NAME} "\$@"
EOF2
  chmod +x "/usr/local/bin/${LEGACY_BIN_NAME}"

  # На некоторых минимальных VPS у root PATH может не содержать /usr/local/bin.
  # Делаем безопасные symlink-fallback в /usr/bin, чтобы команда `ecl` работала сразу после install.sh.
  if [[ -d /usr/bin ]]; then
    ln -sf "/usr/local/bin/${BIN_NAME}" "/usr/bin/${BIN_NAME}"
    ln -sf "/usr/local/bin/${LEGACY_BIN_NAME}" "/usr/bin/${LEGACY_BIN_NAME}"
  fi
}

fix_permissions() {
  find "${APP_DIR}" -type f -name "*.sh" -exec chmod +x {} \;
  chmod +x "${APP_DIR}/menu.sh" "${APP_DIR}/install.sh"
}

verify_install() {
  if ! command -v "${BIN_NAME}" >/dev/null 2>&1; then
    warn "Команда ${BIN_NAME} не найдена через PATH. Запускай напрямую: /usr/local/bin/${BIN_NAME}"
    return 0
  fi
  ok "Команда ${BIN_NAME} доступна: $(command -v "${BIN_NAME}")"
}

main() {
  need_root

  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

  if [[ -f "${script_dir}/menu.sh" && -d "${script_dir}/modules" && -d "${script_dir}/core" ]]; then
    install_from_local_tree "${script_dir}"
  else
    install_from_github
  fi

  fix_permissions
  create_command
  verify_install

  ok "Установка завершена. Запуск меню: ecl"
}

main "$@"
