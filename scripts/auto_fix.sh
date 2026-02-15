#!/usr/bin/env bash
set -euo pipefail

REQUIRED_LABEL_1="${AUTOFIX_LABEL_1:-autofix}"
REQUIRED_LABEL_2="${AUTOFIX_LABEL_2:-bug}"
BRANCH_PREFIX="${AUTOFIX_BRANCH_PREFIX:-autofix/issue-}"

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

git fetch origin "${default_branch}"
git checkout -B "${branch}" "origin/${default_branch}"

echo "running auto fix command: ${autofix_cmd}"
if ! bash -lc "${autofix_cmd}"; then
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
  --body "Automated fix attempt for #${issue_number}.\n\n- Source issue: #${issue_number}\n- Strategy: execute command from issue field **Auto Fix Command**"

echo "created PR for issue #${issue_number}"
