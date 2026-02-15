# ios_rank_history

Node-based daily iOS ranking sync with GitHub automation.

## Scripts

- `npm run sync:ios-rank`: fetch Apple RSS ranking feed and save data files.
- `npm run rank:daily`: generate Markdown report from latest data.
- `npm test`: run smoke tests.

## Environment variables

- `APPSTORE_COUNTRY` (default: `cn`)
- `APPSTORE_LIMIT` (default: `100`)
- `APPSTORE_FEED` (default: `topfreeapplications`)
- `FETCH_RETRIES` (default: `3`)
- `FETCH_RETRY_DELAY_MS` (default: `1500`)
- `APPSTORE_FALLBACK_FILE` (optional; local JSON path when remote fetch is unavailable)

## Data outputs

- `data/latest.json`
- `data/YYYY-MM-DD.json`
- `data/history.ndjson`
- `reports/daily-YYYY-MM-DD.md`

## Automation

Workflows installed:
- `.github/workflows/daily-inspect.yml`
- `.github/workflows/daily-rank-sync.yml`
- `.github/workflows/auto-fix.yml`
- `.github/workflows/auto-merge-low-risk.yml`

## Automation controls

- Low-risk auto-merge:
  - PR with labels `low-risk` + `automerge` will enable GitHub auto-merge (squash).
  - `daily-rank-sync` PRs are labeled automatically.

- Auto-fix circuit breaker:
  - Failed auto-fix attempts will add labels `autofix-failed-1`, `autofix-failed-2`, ...
  - When reaching `AUTOFIX_MAX_FAILURES` (default `3`), issue gets `autofix-blocked`.

- Webhook notifications:
  - Set `NOTIFY_WEBHOOK_URL` in repository Secrets.
  - Optional variable `NOTIFY_PROVIDER` in repository Variables: `feishu` / `wecom` / `slack`.
