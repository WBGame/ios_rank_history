#!/usr/bin/env bash
set -euo pipefail

LATEST_JSON="${LATEST_JSON:-data/latest.json}"
EXPECTED_COUNTRIES="${EXPECTED_COUNTRIES:-${APPSTORE_COUNTRIES:-}}"
EXPECTED_MEDIA_TYPES="${EXPECTED_MEDIA_TYPES:-${APPSTORE_MEDIA_TYPES:-apps}}"
EXPECTED_FEEDS="${EXPECTED_FEEDS:-${APPSTORE_FEEDS:-${APPSTORE_FEED:-top-free}}}"
MIN_COVERAGE_RATIO="${MIN_COVERAGE_RATIO:-1.0}"

if [[ ! -f "${LATEST_JSON}" ]]; then
  echo "[error] latest json not found: ${LATEST_JSON}" >&2
  exit 1
fi

exp_c_count="$(printf '%s' "${EXPECTED_COUNTRIES}" | awk -F',' '{print NF}')"
exp_m_count="$(printf '%s' "${EXPECTED_MEDIA_TYPES}" | awk -F',' '{print NF}')"
exp_f_count="$(printf '%s' "${EXPECTED_FEEDS}" | awk -F',' '{print NF}')"
expected_total=$((exp_c_count * exp_m_count * exp_f_count))

actual_total="$(jq -r '.datasets | length' "${LATEST_JSON}")"

coverage="$(awk -v a="${actual_total}" -v e="${expected_total}" 'BEGIN{ if (e==0) {print 1.0} else {printf "%.4f", a/e} }')"

echo "[info] expected_total=${expected_total} actual_total=${actual_total} coverage=${coverage}"

# Print missing combinations for debugging.
jq -r '.datasets[] | "\(.country|ascii_upcase),\(.mediaType),\(.feedType)"' "${LATEST_JSON}" | sort -u > /tmp/actual-combos.txt

IFS=',' read -r -a c_arr <<< "${EXPECTED_COUNTRIES}"
IFS=',' read -r -a m_arr <<< "${EXPECTED_MEDIA_TYPES}"
IFS=',' read -r -a f_arr <<< "${EXPECTED_FEEDS}"
: > /tmp/expected-combos.txt
for c in "${c_arr[@]}"; do
  c_up="$(printf '%s' "$c" | tr '[:lower:]' '[:upper:]' | xargs)"
  for m in "${m_arr[@]}"; do
    m_l="$(printf '%s' "$m" | tr '[:upper:]' '[:lower:]' | xargs)"
    for f in "${f_arr[@]}"; do
      f_l="$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]' | xargs)"
      [[ -z "$c_up" || -z "$m_l" || -z "$f_l" ]] && continue
      printf '%s,%s,%s\n' "$c_up" "$m_l" "$f_l" >> /tmp/expected-combos.txt
    done
  done
done

missing_count="$(comm -23 <(sort -u /tmp/expected-combos.txt) <(sort -u /tmp/actual-combos.txt) | tee /tmp/missing-combos.txt | wc -l | tr -d ' ')"
if [[ "${missing_count}" != "0" ]]; then
  echo "[warn] missing combinations (${missing_count}):"
  sed -n '1,80p' /tmp/missing-combos.txt
fi

if awk -v c="${coverage}" -v m="${MIN_COVERAGE_RATIO}" 'BEGIN{exit !(c>=m)}'; then
  echo "[done] data validation passed"
else
  echo "[error] coverage ${coverage} < min ${MIN_COVERAGE_RATIO}" >&2
  exit 1
fi
