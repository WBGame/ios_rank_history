#!/usr/bin/env bash
set -euo pipefail

REQUIRED_LABEL_1="${AUTOFIX_LABEL_1:-autofix}"
REQUIRED_LABEL_2="${AUTOFIX_LABEL_2:-bug}"
BRANCH_PREFIX="${AUTOFIX_BRANCH_PREFIX:-autofix/issue-}"
MAX_FAILURES="${AUTOFIX_MAX_FAILURES:-3}"
FAIL_LABEL_PREFIX="${AUTOFIX_FAIL_LABEL_PREFIX:-autofix-failed-}"
BLOCK_LABEL="${AUTOFIX_BLOCK_LABEL:-autofix-blocked}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh cli is required" >&2
  exit 1
fi

issue_json="$(gh issue list \
  --state open \
  --label "${REQUIRED_LABEL_1}" \
  --label "${REQUIRED_LABEL_2}" \
  --limit 1 \
  --json number,title,body,url)"

issue_number="$(echo "${issue_json}" | jq -r '.[0].number // empty')"
issue_title="$(echo "${issue_json}" | jq -r '.[0].title // empty')"
issue_body="$(echo "${issue_json}" | jq -r '.[0].body // empty')"

if [[ -z "${issue_number}" ]]; then
  echo "no open issues with labels ${REQUIRED_LABEL_1}+${REQUIRED_LABEL_2}"
  exit 0
fi

issue_labels="$(gh issue view "${issue_number}" --json labels --jq '.labels[].name' 2>/dev/null || true)"

if printf '%s\n' "${issue_labels}" | grep -qx "${BLOCK_LABEL}"; then
  echo "issue #${issue_number} is blocked by ${BLOCK_LABEL}"
  exit 0
fi

autofix_cmd="$(printf '%s\n' "${issue_body}" | awk '
  /^### Auto Fix Command/ {in_block=1; next}
  /^### / && in_block==1 {in_block=0}
  in_block==1 {print}
' | sed -n 's/.*`\([^`]*\)`.*/\1/p' | head -n1)"

if [[ -z "${autofix_cmd}" ]]; then
  echo "issue #${issue_number} has no parseable Auto Fix Command"
  exit 0
fi

default_branch="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"
branch="${BRANCH_PREFIX}${issue_number}"
log_file="/tmp/autofix-issue-${issue_number}.log"

current_fail_count="$(printf '%s\n' "${issue_labels}" | sed -n "s/^${FAIL_LABEL_PREFIX}\([0-9][0-9]*\)$/\1/p" | sort -nr | head -n1)"
current_fail_count="${current_fail_count:-0}"

git fetch origin "${default_branch}"
git checkout -B "${branch}" "origin/${default_branch}"

echo "running auto fix command: ${autofix_cmd}"
if ! bash -lc "${autofix_cmd}" >"${log_file}" 2>&1; then
  next_fail_count=$((current_fail_count + 1))
  fail_label="${FAIL_LABEL_PREFIX}${next_fail_count}"
  gh issue edit "${issue_number}" --add-label "${fail_label}" >/dev/null || true

  if (( next_fail_count >= MAX_FAILURES )); then
    gh issue edit "${issue_number}" --add-label "${BLOCK_LABEL}" >/dev/null || true
    gh issue edit "${issue_number}" --remove-label "${REQUIRED_LABEL_1}" >/dev/null || true
  fi

  gh issue comment "${issue_number}" --body "$(cat <<EOF
Auto-fix failed on attempt ${next_fail_count}/${MAX_FAILURES}.

- Command: \`${autofix_cmd}\`
- Action: ${fail_label} added$( (( next_fail_count >= MAX_FAILURES )) && printf ', issue blocked with %s' "${BLOCK_LABEL}" )

\`\`\`text
$(tail -n 40 "${log_file}" 2>/dev/null || echo "no logs")
\`\`\`
EOF
)" >/dev/null || true

  echo "auto fix command failed"
  exit 1
fi

if git diff --quiet; then
  echo "no changes after auto fix command"
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git add -A
git commit -m "fix: auto-resolve #${issue_number} ${issue_title}"
git push -u origin "${branch}" --force

existing_pr="$(gh pr list --state open --head "${branch}" --json number --jq '.[0].number // empty')"
if [[ -n "${existing_pr}" ]]; then
  echo "pr #${existing_pr} already exists"
  exit 0
fi

gh pr create \
  --base "${default_branch}" \
  --head "${branch}" \
  --title "fix: auto-resolve #${issue_number}" \
  --label "autofix" \
  --label "needs-review" \
  --body "Automated fix attempt for #${issue_number}.\n\n- Source issue: #${issue_number}\n- Strategy: execute command from issue field **Auto Fix Command**"

for i in $(seq 1 "${MAX_FAILURES}"); do
  gh issue edit "${issue_number}" --remove-label "${FAIL_LABEL_PREFIX}${i}" >/dev/null || true
done
gh issue edit "${issue_number}" --remove-label "${BLOCK_LABEL}" >/dev/null || true

echo "created PR for issue #${issue_number}"
