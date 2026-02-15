#!/usr/bin/env bash
set -euo pipefail

REPORT_FILE="${1:-daily-report.md}"
TITLE_PREFIX="${TITLE_PREFIX:-[Daily Improvement]}"
LABELS="${ISSUE_LABELS:-daily-check,improvement}"
TODAY="$(date +%F)"
TITLE="${TITLE_PREFIX} ${TODAY}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh cli is required" >&2
  exit 1
fi

if [[ ! -f "${REPORT_FILE}" ]]; then
  echo "report file not found: ${REPORT_FILE}" >&2
  exit 1
fi

ISSUE_NUMBER="$(gh issue list --state open --search "in:title ${TITLE}" --json number,title --jq '.[] | select(.title == "'"${TITLE}"'") | .number' | head -n1 || true)"

if [[ -n "${ISSUE_NUMBER}" ]]; then
  gh issue comment "${ISSUE_NUMBER}" --body-file "${REPORT_FILE}"
  echo "updated existing issue #${ISSUE_NUMBER}"
else
  gh issue create \
    --title "${TITLE}" \
    --label "${LABELS}" \
    --body-file "${REPORT_FILE}"
  echo "created new daily improvement issue"
fi
