#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "GITHUB_REPOSITORY is required" >&2
  exit 1
fi

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "GH_TOKEN is required" >&2
  exit 1
fi

WORKDIR="${WORKDIR:-$PWD}"
REPORT_DIR="${REPORT_DIR:-${WORKDIR}/reports}"
DATA_DIR="${DATA_DIR:-${WORKDIR}/data}"
LATEST_JSON="${LATEST_JSON:-${DATA_DIR}/latest.json}"
TMP_DIR="${TMP_DIR:-/tmp/wiki-sync-$$}"
WIKI_DIR="${TMP_DIR}/wiki"
REPO_URL="https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.wiki.git"
CLONE_LOG="${TMP_DIR}/clone.log"

mkdir -p "${TMP_DIR}"

if ! git clone "${REPO_URL}" "${WIKI_DIR}" >"${CLONE_LOG}" 2>&1; then
  echo "[warn] failed to clone wiki repo, try bootstrap mode"
  mkdir -p "${WIKI_DIR}"
  git -C "${WIKI_DIR}" init -b master >/dev/null 2>&1 || git -C "${WIKI_DIR}" init >/dev/null 2>&1
  git -C "${WIKI_DIR}" remote add origin "${REPO_URL}"
fi

latest_report="$(ls -1 "${REPORT_DIR}"/daily-*.md 2>/dev/null | sort | tail -n1 || true)"
if [[ -z "${latest_report}" ]]; then
  echo "[warn] no report file found in ${REPORT_DIR}"
  exit 0
fi

latest_date="$(basename "${latest_report}" | sed -E 's/^daily-([0-9]{4}-[0-9]{2}-[0-9]{2})\.md$/\1/')"
cp "${latest_report}" "${WIKI_DIR}/Latest.md"

# Sync report pages
ls -1 "${REPORT_DIR}"/daily-*.md 2>/dev/null | sort -r | head -n "${WIKI_RECENT_LIMIT:-30}" | while read -r f; do
  d="$(basename "$f" | sed -E 's/^daily-([0-9]{4}-[0-9]{2}-[0-9]{2})\.md$/\1/')"
  cp "$f" "${WIKI_DIR}/Daily-${d}.md"
done

WORKDIR="${WORKDIR}" \
REPORT_DIR="${REPORT_DIR}" \
DATA_DIR="${DATA_DIR}" \
LATEST_JSON="${LATEST_JSON}" \
WIKI_DIR="${WIKI_DIR}" \
GITHUB_REPOSITORY="${GITHUB_REPOSITORY}" \
WIKI_TOP_N="${WIKI_TOP_N:-10}" \
WIKI_MOVER_N="${WIKI_MOVER_N:-5}" \
WIKI_RECENT_LIMIT="${WIKI_RECENT_LIMIT:-30}" \
WIKI_COUNTRIES="${WIKI_COUNTRIES:-}" \
WIKI_MEDIA_TYPES="${WIKI_MEDIA_TYPES:-}" \
node "${WORKDIR}/scripts/build_wiki_pages.mjs"

cd "${WIKI_DIR}"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git add .
if git diff --cached --quiet; then
  echo "[done] wiki is up to date"
  exit 0
fi

git commit -m "docs: update wiki rankings ${latest_date}" >/dev/null
if ! git push origin master >/dev/null 2>&1 && ! git push origin main >/dev/null 2>&1; then
  echo "[error] failed to push wiki pages"
  if [[ -f "${CLONE_LOG}" ]]; then
    echo "[debug] clone error:"
    sed -n '1,120p' "${CLONE_LOG}"
  fi
  exit 1
fi

echo "[done] wiki updated: Daily-${latest_date}.md"
