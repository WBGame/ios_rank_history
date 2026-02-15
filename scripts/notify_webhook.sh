#!/usr/bin/env bash
set -euo pipefail

WEBHOOK_URL="${NOTIFY_WEBHOOK_URL:-}"
PROVIDER="${NOTIFY_PROVIDER:-feishu}"
STATUS="${NOTIFY_STATUS:-info}"
TITLE="${NOTIFY_TITLE:-GitHub Automation}"
MESSAGE="${NOTIFY_MESSAGE:-No message}"

if [[ -z "${WEBHOOK_URL}" ]]; then
  echo "notify skipped: NOTIFY_WEBHOOK_URL is empty"
  exit 0
fi

full_text="[${STATUS}] ${TITLE}\n${MESSAGE}"

case "${PROVIDER}" in
  feishu)
    payload="$(jq -n --arg text "${full_text}" '{msg_type:"text",content:{text:$text}}')"
    ;;
  wecom)
    payload="$(jq -n --arg text "${full_text}" '{msgtype:"text",text:{content:$text}}')"
    ;;
  slack)
    payload="$(jq -n --arg text "${full_text}" '{text:$text}')"
    ;;
  *)
    payload="$(jq -n --arg text "${full_text}" '{text:$text}')"
    ;;
esac

curl -sS -X POST "${WEBHOOK_URL}" \
  -H 'Content-Type: application/json' \
  -d "${payload}" >/dev/null

echo "notify sent via ${PROVIDER}"
