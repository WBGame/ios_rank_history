#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-data}"
REPORT_DIR="${REPORT_DIR:-reports}"
RETENTION_DAYS="${DATA_RETENTION_DAYS:-14}"
PRUNE_ARCHIVE_DIR="${PRUNE_ARCHIVE_DIR:-}"

if [[ ! -d "${DATA_DIR}" ]]; then
  echo "[warn] data dir not found: ${DATA_DIR}"
  exit 0
fi

old_data_files="$(find "${DATA_DIR}" -type f -name '20??-??-??*.json' -mtime +"${RETENTION_DAYS}" | sort || true)"
old_report_files="$(find "${REPORT_DIR}" -type f -name 'daily-20??-??-??.md' -mtime +"${RETENTION_DAYS}" | sort || true)"
old_files_combined="$(printf '%s\n%s\n' "${old_data_files}" "${old_report_files}" | sed '/^$/d')"

if [[ -z "${old_files_combined}" ]]; then
  echo "[done] no old files to prune"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "archive_file=" >> "${GITHUB_OUTPUT}"
  fi
  exit 0
fi

archive_file=""
if [[ -n "${PRUNE_ARCHIVE_DIR}" ]]; then
  mkdir -p "${PRUNE_ARCHIVE_DIR}"
  ts="$(date +%Y%m%d-%H%M%S)"
  archive_file="${PRUNE_ARCHIVE_DIR}/pruned-${ts}.tar.gz"
  printf '%s\n' "${old_files_combined}" | tar -czf "${archive_file}" -T -
  echo "[info] archived old files -> ${archive_file}"
fi

printf '%s\n' "${old_files_combined}" | while read -r f; do
  rm -f "$f"
  echo "[pruned] $f"
done

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "archive_file=${archive_file}" >> "${GITHUB_OUTPUT}"
fi

echo "[done] prune completed"
