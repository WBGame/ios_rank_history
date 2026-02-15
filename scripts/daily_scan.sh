#!/usr/bin/env bash
set -euo pipefail

REPORT_FILE="${1:-daily-report.md}"
TODAY="$(date +%F)"
RULES_FILE="${RULES_FILE:-config/rules.yml}"

{
  echo "# Daily Scan Report (${TODAY})"
  echo
  echo "## Repository"
  echo "- Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  echo "- Commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo
  echo "## Build / Check Commands"
} > "${REPORT_FILE}"

if [[ -n "${SCAN_COMMANDS:-}" ]]; then
  IFS=$'\n' read -r -d '' -a CMDS < <(printf '%s\0' "${SCAN_COMMANDS}") || true
elif [[ -f "${RULES_FILE}" ]]; then
  CMDS=()
  while IFS= read -r line; do
    CMDS+=("${line}")
  done < <(awk '
    /^scan:/ {in_scan=1; next}
    /^[a-zA-Z_]+:/ && in_scan==1 {in_scan=0}
    in_scan==1 && /^  commands:/ {in_cmd=1; next}
    in_scan==1 && /^  [a-zA-Z_]+:/ && in_cmd==1 {in_cmd=0}
    in_scan==1 && in_cmd==1 && /^[[:space:]]*-[[:space:]]*"/ {
      line=$0
      sub(/^[[:space:]]*-[[:space:]]*"/, "", line)
      sub(/"$/, "", line)
      print line
    }
  ' "${RULES_FILE}")
  if [[ ${#CMDS[@]} -eq 0 ]]; then
    CMDS=("echo '[scan] rules.yml found but no scan.commands parsed'")
  fi
else
  CMDS=("echo '[scan] no SCAN_COMMANDS configured'")
fi

for cmd in "${CMDS[@]}"; do
  [[ -z "${cmd}" ]] && continue
  {
    echo
    echo "### \`${cmd}\`"
    echo '```text'
  } >> "${REPORT_FILE}"

  if bash -lc "${cmd}" >> "${REPORT_FILE}" 2>&1; then
    echo "[ok] command succeeded" >> "${REPORT_FILE}"
  else
    echo "[fail] command failed" >> "${REPORT_FILE}"
  fi

  echo '```' >> "${REPORT_FILE}"
done

{
  echo
  echo "## Code Smells (TODO/FIXME)"
  echo '```text'
} >> "${REPORT_FILE}"

if command -v rg >/dev/null 2>&1; then
  rg -n "TODO|FIXME" --glob '!node_modules' --glob '!.git' . >> "${REPORT_FILE}" 2>/dev/null || true
else
  grep -RIn "TODO\|FIXME" . --exclude-dir=.git --exclude-dir=node_modules >> "${REPORT_FILE}" 2>/dev/null || true
fi

echo '```' >> "${REPORT_FILE}"
echo "[done] report written to ${REPORT_FILE}"
