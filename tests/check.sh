#!/usr/bin/env bash
# Static checks for the ECL VPS Kit.
#   - bash -n  : syntax check every shell script
#   - shellcheck: lint (if installed)
# Usage: bash tests/check.sh
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
cd "${ROOT}"

mapfile -t scripts < <(
  find . -path ./.git -prune -o -name '*.sh' -print
  printf '%s\n' ./menu.sh
)
# de-dup
mapfile -t scripts < <(printf '%s\n' "${scripts[@]}" | sort -u)

fails=0

echo "== bash -n (syntax) =="
for f in "${scripts[@]}"; do
  [[ -f "${f}" ]] || continue
  if bash -n "${f}"; then
    echo "  ok   ${f}"
  else
    echo "  FAIL ${f}"
    fails=$((fails + 1))
  fi
done

echo
if command -v shellcheck >/dev/null 2>&1; then
  echo "== shellcheck =="
  for f in "${scripts[@]}"; do
    [[ -f "${f}" ]] || continue
    if shellcheck -x -S warning "${f}"; then
      echo "  ok   ${f}"
    else
      fails=$((fails + 1))
    fi
  done
else
  echo "== shellcheck пропущен (не установлен) =="
fi

echo
if (( fails == 0 )); then
  echo "Все проверки пройдены."
else
  echo "Проблемы: ${fails}"
  exit 1
fi
