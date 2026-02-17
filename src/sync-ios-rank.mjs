import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

const COUNTRY = process.env.APPSTORE_COUNTRY || 'cn';
const LIMIT = Number.parseInt(process.env.APPSTORE_LIMIT || '100', 10);
const FEED_TYPE = process.env.APPSTORE_FEED || 'top-free';
const DATA_DIR = process.env.DATA_DIR || 'data';
const MAX_RETRIES = Number.parseInt(process.env.FETCH_RETRIES || '3', 10);
const RETRY_DELAY_MS = Number.parseInt(process.env.FETCH_RETRY_DELAY_MS || '1500', 10);
const FALLBACK_FILE = process.env.APPSTORE_FALLBACK_FILE || '';

const today = new Date().toISOString().slice(0, 10);
function normalizeFeedAlias(feed) {
  const text = String(feed || '').trim().toLowerCase();
  if (!text) return 'top-free';
  if (text === 'topfreeapplications') return 'top-free';
  if (text === 'toppaidapplications') return 'top-paid';
  if (text === 'topgrossingapplications') return 'top-grossing';
  return text;
}

function buildFeedCandidates(feed) {
  const normalized = normalizeFeedAlias(feed);
  const set = new Set([normalized]);
  if (normalized.includes('topfree')) set.add('top-free');
  if (normalized.includes('toppaid')) set.add('top-paid');
  if (normalized.includes('topgrossing')) set.add('top-grossing');
  return [...set];
}

function buildFeedUrl(feed) {
  return `https://rss.applemarketingtools.com/api/v2/${COUNTRY}/apps/${feed}/${LIMIT}/apps.json`;
}

async function fetchJson(url) {
  let lastError;

  for (let i = 1; i <= MAX_RETRIES; i += 1) {
    try {
      const response = await fetch(url, {
        headers: {
          'User-Agent': 'ios-rank-history-bot/1.0'
        }
      });

      if (!response.ok) {
        throw new Error(`Fetch failed: ${response.status} ${response.statusText}`);
      }

      return response.json();
    } catch (err) {
      lastError = err;
      if (i < MAX_RETRIES) {
        await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
      }
    }
  }

  if (FALLBACK_FILE && existsSync(FALLBACK_FILE)) {
    const fallbackRaw = await readFile(FALLBACK_FILE, 'utf8');
    return JSON.parse(fallbackRaw);
  }

  throw lastError;
}

function normalizeItems(raw) {
  const list = raw?.feed?.results || [];
  return list.map((item, idx) => ({
    date: today,
    rank: idx + 1,
    id: item.id,
    name: item.name,
    artistName: item.artistName,
    kind: item.kind,
    releaseDate: item.releaseDate,
    artworkUrl100: item.artworkUrl100,
    url: item.url
  }));
}

async function main() {
  await mkdir(DATA_DIR, { recursive: true });

  let raw;
  let resolvedFeed = FEED_TYPE;
  let resolvedUrl = '';
  let fetchError;

  for (const candidate of buildFeedCandidates(FEED_TYPE)) {
    const candidateUrl = buildFeedUrl(candidate);
    try {
      raw = await fetchJson(candidateUrl);
      resolvedFeed = candidate;
      resolvedUrl = candidateUrl;
      break;
    } catch (err) {
      fetchError = err;
    }
  }

  if (!raw) {
    throw fetchError || new Error('failed to fetch any appstore feed');
  }

  const items = normalizeItems(raw);

  const dailyFile = join(DATA_DIR, `${today}.json`);
  const latestFile = join(DATA_DIR, 'latest.json');
  const historyFile = join(DATA_DIR, 'history.ndjson');

  const payload = {
    date: today,
    country: COUNTRY,
    feedType: resolvedFeed,
    limit: LIMIT,
    source: resolvedUrl,
    total: items.length,
    items
  };

  await writeFile(dailyFile, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
  await writeFile(latestFile, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');

  const existing = existsSync(historyFile) ? await readFile(historyFile, 'utf8') : '';
  const alreadySynced = existing.split('\n').filter(Boolean).some((line) => {
    try {
      const row = JSON.parse(line);
      return row.date === today && row.country === COUNTRY && row.feedType === resolvedFeed;
    } catch {
      return false;
    }
  });

  if (!alreadySynced) {
    await writeFile(
      historyFile,
      `${existing}${JSON.stringify({
        date: today,
        country: COUNTRY,
        feedType: resolvedFeed,
        limit: LIMIT,
        total: items.length,
        source: resolvedUrl,
        top10: items.slice(0, 10)
      })}\n`,
      'utf8'
    );
  }

  console.log(`synced ${items.length} apps to ${dailyFile}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
