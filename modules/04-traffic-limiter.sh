#!/usr/bin/env bash
# Deprecated alias. The traffic shaper/limiter now lives entirely in
# 04-traffic-shaper.sh (single source of truth). This shim stays only so
# older calls to 04-traffic-limiter.sh keep working.
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/ecl-vps-kit}"
exec bash "${APP_DIR}/modules/04-traffic-shaper.sh" "$@"
