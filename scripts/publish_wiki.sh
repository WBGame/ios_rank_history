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
LATEST_JSON="${LATEST_JSON:-${WORKDIR}/data/latest.json}"
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
daily_page="Daily-${latest_date}.md"
latest_link_page="Latest.md"

report_countries="$(sed -n 's/^- Countries: //p' "${latest_report}" | head -n1)"
report_media_types="$(sed -n 's/^- Media Types: //p' "${latest_report}" | head -n1)"
report_feeds="$(sed -n 's/^- Feeds: //p' "${latest_report}" | head -n1)"
report_total_datasets="$(sed -n 's/^- Total datasets: //p' "${latest_report}" | head -n1)"

if command -v jq >/dev/null 2>&1 && [[ -f "${LATEST_JSON}" ]]; then
  report_countries="$(jq -r '[.datasets[].country | ascii_upcase] | unique | join(", ")' "${LATEST_JSON}" 2>/dev/null || echo "${report_countries}")"
  report_media_types="$(jq -r '[.datasets[].mediaType] | unique | join(", ")' "${LATEST_JSON}" 2>/dev/null || echo "${report_media_types}")"
  report_feeds="$(jq -r '[.datasets[].feedType] | unique | join(", ")' "${LATEST_JSON}" 2>/dev/null || echo "${report_feeds}")"
  report_total_datasets="$(jq -r '.datasets | length' "${LATEST_JSON}" 2>/dev/null || echo "${report_total_datasets}")"
fi

cp "${latest_report}" "${WIKI_DIR}/${daily_page}"
cp "${latest_report}" "${WIKI_DIR}/${latest_link_page}"

{
  echo "# iOS Rank Wiki"
  echo
  echo "| Item | Value |"
  echo "| --- | --- |"
  echo "| Latest update | ${latest_date} |"
  echo "| Repository | [${GITHUB_REPOSITORY}](https://github.com/${GITHUB_REPOSITORY}) |"
  echo "| Countries | ${report_countries:-N/A} |"
  echo "| Media Types | ${report_media_types:-N/A} |"
  echo "| Feeds | ${report_feeds:-N/A} |"
  echo "| Total datasets | ${report_total_datasets:-N/A} |"
  echo
  echo "## Quick Links"
  echo
  echo "- [Latest report](${latest_link_page})"
  echo "- [${daily_page}](${daily_page})"
  echo
  echo "## Navigation"
  echo
  echo "- [Home](Home)"
  echo "- [Latest](${latest_link_page})"
  echo "- [Recent reports](#recent-reports)"
  echo
  echo "## Recent Reports"
  echo
  echo "| Date | Page |"
  echo "| --- | --- |"
  ls -1 "${REPORT_DIR}"/daily-*.md 2>/dev/null | sort -r | head -n 30 | while read -r f; do
    d="$(basename "$f" | sed -E 's/^daily-([0-9]{4}-[0-9]{2}-[0-9]{2})\.md$/\1/')"
    echo "| ${d} | [Daily-${d}.md](Daily-${d}.md) |"
  done
} > "${WIKI_DIR}/Home.md"

{
  echo "## Wiki Navigation"
  echo
  echo "- [Home](Home)"
  echo "- [Latest](${latest_link_page})"
  echo
  echo "### Recent Reports"
  ls -1 "${REPORT_DIR}"/daily-*.md 2>/dev/null | sort -r | head -n 20 | while read -r f; do
    d="$(basename "$f" | sed -E 's/^daily-([0-9]{4}-[0-9]{2}-[0-9]{2})\.md$/\1/')"
    echo "- [Daily-${d}.md](Daily-${d}.md)"
  done
} > "${WIKI_DIR}/_Sidebar.md"

if command -v jq >/dev/null 2>&1 && [[ -f "${LATEST_JSON}" ]]; then
  {
    echo
    echo "## Top 10 Snapshot"
    echo
    media_types="$(jq -r '.datasets[].mediaType' "${LATEST_JSON}" | sort -u)"
    while IFS= read -r media; do
      [[ -z "${media}" ]] && continue
      echo "### ${media^^}"
      echo
      jq -c --arg media "${media}" '
        .datasets
        | map(select(.mediaType == $media))
        | sort_by(.country, .feedType)
        | .[]
      ' "${LATEST_JSON}" | while IFS= read -r row; do
        country="$(printf '%s' "${row}" | jq -r '.country | ascii_upcase')"
        feed="$(printf '%s' "${row}" | jq -r '.feedType')"
        echo "#### ${country} · ${feed}"
        echo
        echo "| Rank | App |"
        echo "| --- | --- |"
        printf '%s' "${row}" | jq -r '
          def esc: gsub("\\|"; "\\\\|");
          .items
          | to_entries
          | .[:10]
          | .[]
          | "| \(.key + 1) | \(.value.name | esc) |"
        '
        echo
      done
    done <<< "${media_types}"
  } >> "${WIKI_DIR}/Home.md"
fi

# Sync recent report pages
ls -1 "${REPORT_DIR}"/daily-*.md 2>/dev/null | sort -r | head -n 30 | while read -r f; do
  d="$(basename "$f" | sed -E 's/^daily-([0-9]{4}-[0-9]{2}-[0-9]{2})\.md$/\1/')"
  cp "$f" "${WIKI_DIR}/Daily-${d}.md"
done

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

echo "[done] wiki updated: ${daily_page}"
