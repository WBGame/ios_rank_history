import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

const LEGACY_COUNTRY = process.env.APPSTORE_COUNTRY || '';
const COUNTRIES = (
  process.env.APPSTORE_COUNTRIES ||
  (LEGACY_COUNTRY ? LEGACY_COUNTRY : 'cn,us,jp')
)
  .split(',')
  .map((v) => v.trim().toLowerCase())
  .filter(Boolean);

const FEED_INPUT = process.env.APPSTORE_FEEDS || process.env.APPSTORE_FEED || 'top-free';
const LIMIT = Number.parseInt(process.env.APPSTORE_LIMIT || '100', 10);
const DATA_DIR = process.env.DATA_DIR || 'data';
const MAX_RETRIES = Number.parseInt(process.env.FETCH_RETRIES || '3', 10);
const RETRY_DELAY_MS = Number.parseInt(process.env.FETCH_RETRY_DELAY_MS || '1500', 10);
const FETCH_CONCURRENCY = Math.max(
  1,
  Number.parseInt(process.env.FETCH_CONCURRENCY || '3', 10)
);
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

const FEEDS = [...new Set(FEED_INPUT.split(',').map((f) => normalizeFeedAlias(f)).filter(Boolean))];

function buildFeedCandidates(feed) {
  const normalized = normalizeFeedAlias(feed);
  const set = new Set([normalized]);
  if (normalized.includes('topfree')) set.add('top-free');
  if (normalized.includes('toppaid')) set.add('top-paid');
  if (normalized.includes('topgrossing')) set.add('top-grossing');
  return [...set];
}

function buildFeedUrl(country, feed) {
  return `https://rss.applemarketingtools.com/api/v2/${country}/apps/${feed}/${LIMIT}/apps.json`;
}

function fileSafeFeed(feed) {
  return feed.replace(/[^a-z0-9-]/g, '-');
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

async function fetchDataset(country, feedInputItem) {
  let raw;
  let resolvedFeed = normalizeFeedAlias(feedInputItem);
  let resolvedUrl = '';
  let fetchError;

  for (const candidate of buildFeedCandidates(feedInputItem)) {
    const candidateUrl = buildFeedUrl(country, candidate);
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
    throw fetchError || new Error(`failed to fetch feed=${feedInputItem} for country=${country}`);
  }

  const items = normalizeItems(raw);
  return {
    date: today,
    country,
    mediaType: 'apps',
    feedType: resolvedFeed,
    limit: LIMIT,
    source: resolvedUrl,
    total: items.length,
    items
  };
}

async function runWithConcurrency(taskFns, limit) {
  const results = new Array(taskFns.length);
  let cursor = 0;

  async function worker() {
    while (true) {
      const idx = cursor;
      cursor += 1;
      if (idx >= taskFns.length) return;
      results[idx] = await taskFns[idx]();
    }
  }

  const workers = Array.from({ length: Math.min(limit, taskFns.length) }, () => worker());
  await Promise.all(workers);
  return results;
}

async function main() {
  await mkdir(DATA_DIR, { recursive: true });

  const taskFns = [];
  for (const country of COUNTRIES) {
    for (const feed of FEEDS) {
      taskFns.push(async () => {
        try {
          const dataset = await fetchDataset(country, feed);
          return { ok: true, country, feed, dataset };
        } catch (err) {
          return {
            ok: false,
            country,
            feed,
            error: err instanceof Error ? err.message : String(err)
          };
        }
      });
    }
  }

  const taskResults = await runWithConcurrency(taskFns, FETCH_CONCURRENCY);
  const datasets = taskResults.filter((r) => r.ok).map((r) => r.dataset);
  const errors = taskResults.filter((r) => !r.ok);

  if (datasets.length === 0) {
    throw new Error('all dataset fetches failed');
  }

  const aggregate = {
    date: today,
    countries: COUNTRIES,
    mediaType: 'apps',
    feedTypes: FEEDS,
    limit: LIMIT,
    totalDatasets: datasets.length,
    warnings: errors,
    datasets
  };

  const dailyFile = join(DATA_DIR, `${today}.json`);
  const latestFile = join(DATA_DIR, 'latest.json');
  const historyFile = join(DATA_DIR, 'history.ndjson');

  await writeFile(dailyFile, `${JSON.stringify(aggregate, null, 2)}\n`, 'utf8');
  await writeFile(latestFile, `${JSON.stringify(aggregate, null, 2)}\n`, 'utf8');

  for (const country of COUNTRIES) {
    const countryDatasets = datasets.filter((d) => d.country === country);

    const countryAggregate = {
      date: today,
      country,
      mediaType: 'apps',
      feedTypes: countryDatasets.map((d) => d.feedType),
      limit: LIMIT,
      totalDatasets: countryDatasets.length,
      datasets: countryDatasets
    };

    await writeFile(join(DATA_DIR, `latest-${country}.json`), `${JSON.stringify(countryAggregate, null, 2)}\n`, 'utf8');
    await writeFile(join(DATA_DIR, `${today}-${country}.json`), `${JSON.stringify(countryAggregate, null, 2)}\n`, 'utf8');
  }

  for (const dataset of datasets) {
    const feedTag = fileSafeFeed(dataset.feedType);
    await writeFile(
      join(DATA_DIR, `latest-${dataset.country}-${feedTag}.json`),
      `${JSON.stringify(dataset, null, 2)}\n`,
      'utf8'
    );
    await writeFile(
      join(DATA_DIR, `${today}-${dataset.country}-${feedTag}.json`),
      `${JSON.stringify(dataset, null, 2)}\n`,
      'utf8'
    );
  }

  const existing = existsSync(historyFile) ? await readFile(historyFile, 'utf8') : '';
  const rows = existing.split('\n').filter(Boolean);

  let out = existing;
  for (const dataset of datasets) {
    const exists = rows.some((line) => {
      try {
        const row = JSON.parse(line);
        return (
          row.date === today &&
          row.country === dataset.country &&
          row.mediaType === dataset.mediaType &&
          row.feedType === dataset.feedType
        );
      } catch {
        return false;
      }
    });

    if (!exists) {
      out += `${JSON.stringify({
        date: today,
        country: dataset.country,
        mediaType: dataset.mediaType,
        feedType: dataset.feedType,
        limit: dataset.limit,
        total: dataset.total,
        source: dataset.source,
        top10: dataset.items.slice(0, 10)
      })}\n`;
    }
  }

  await writeFile(historyFile, out, 'utf8');

  if (errors.length > 0) {
    console.warn(`skipped ${errors.length} failed dataset(s):`);
    for (const err of errors) {
      console.warn(`- country=${err.country} feed=${err.feed} error=${err.error}`);
    }
  }

  console.log(
    `synced ${datasets.length} datasets across ${COUNTRIES.length} countries and ${FEEDS.length} feeds to ${dailyFile}`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
