import { promises as fs } from 'node:fs';
import path from 'node:path';

const WORKDIR = process.env.WORKDIR || process.cwd();
const REPORT_DIR = process.env.REPORT_DIR || path.join(WORKDIR, 'reports');
const DATA_DIR = process.env.DATA_DIR || path.join(WORKDIR, 'data');
const WIKI_DIR = process.env.WIKI_DIR;

if (!WIKI_DIR) {
  throw new Error('WIKI_DIR is required');
}

const TOP_N = Number.parseInt(process.env.WIKI_TOP_N || '10', 10);
const MOVER_N = Number.parseInt(process.env.WIKI_MOVER_N || '5', 10);
const RECENT_LIMIT = Number.parseInt(process.env.WIKI_RECENT_LIMIT || '30', 10);

const countryFilter = (process.env.WIKI_COUNTRIES || '')
  .split(',')
  .map((x) => x.trim().toUpperCase())
  .filter(Boolean);
const mediaFilter = (process.env.WIKI_MEDIA_TYPES || '')
  .split(',')
  .map((x) => x.trim().toLowerCase())
  .filter(Boolean);

function slugify(s) {
  return String(s)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-');
}

function escPipe(s) {
  return String(s || '-').replace(/\|/g, '\\|');
}

function keyOf(d) {
  return `${String(d.country).toUpperCase()}|${String(d.mediaType).toLowerCase()}|${String(d.feedType).toLowerCase()}`;
}

function dedupDatasets(list) {
  const map = new Map();
  for (const d of list || []) {
    const k = keyOf(d);
    if (!map.has(k)) map.set(k, d);
  }
  return [...map.values()];
}

function applyFilters(list) {
  return list.filter((d) => {
    const c = String(d.country).toUpperCase();
    const m = String(d.mediaType || 'apps').toLowerCase();
    if (countryFilter.length && !countryFilter.includes(c)) return false;
    if (mediaFilter.length && !mediaFilter.includes(m)) return false;
    return true;
  });
}

function sortDatasets(list) {
  return [...list].sort((a, b) => {
    const c = String(a.country).localeCompare(String(b.country));
    if (c !== 0) return c;
    const m = String(a.mediaType).localeCompare(String(b.mediaType));
    if (m !== 0) return m;
    return String(a.feedType).localeCompare(String(b.feedType));
  });
}

async function listReports() {
  const entries = await fs.readdir(REPORT_DIR).catch(() => []);
  return entries
    .filter((f) => /^daily-\d{4}-\d{2}-\d{2}\.md$/.test(f))
    .sort()
    .map((f) => ({
      file: f,
      date: f.slice('daily-'.length, 'daily-YYYY-MM-DD'.length)
    }));
}

async function readJsonIfExists(file) {
  try {
    const raw = await fs.readFile(file, 'utf8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function buildPrevRankMaps(prevDatasets) {
  const maps = new Map();
  for (const d of prevDatasets) {
    const rankMap = new Map();
    for (const item of d.items || []) {
      if (item?.id) rankMap.set(String(item.id), Number(item.rank) || null);
    }
    maps.set(keyOf(d), rankMap);
  }
  return maps;
}

function computeMovers(dataset, prevRankMaps) {
  const prev = prevRankMaps.get(keyOf(dataset));
  if (!prev) return [];
  const out = [];
  for (const item of dataset.items || []) {
    const id = String(item?.id || '');
    if (!id) continue;
    const rank = Number(item.rank) || null;
    const prevRank = prev.get(id);
    if (!rank) continue;
    if (!prevRank) {
      out.push({ name: item.name, rank, prev: null, delta: null, state: 'new' });
      continue;
    }
    const delta = prevRank - rank;
    if (delta !== 0) out.push({ name: item.name, rank, prev: prevRank, delta, state: 'moved' });
  }

  out.sort((a, b) => {
    if (a.state !== b.state) return a.state === 'new' ? -1 : 1;
    const ad = Math.abs(a.delta || 0);
    const bd = Math.abs(b.delta || 0);
    if (bd !== ad) return bd - ad;
    return a.rank - b.rank;
  });

  return out.slice(0, MOVER_N);
}

function renderTopTable(lines, dataset) {
  lines.push('| Rank | App |');
  lines.push('| --- | --- |');
  for (const item of (dataset.items || []).slice(0, TOP_N)) {
    lines.push(`| ${item.rank} | ${escPipe(item.name)} |`);
  }
  lines.push('');
}

function renderMoverTable(lines, movers, prevDate) {
  lines.push(`Top movers vs ${prevDate}:`);
  lines.push('');
  if (!movers.length) {
    lines.push('- No rank movement detected.');
    lines.push('');
    return;
  }
  lines.push('| App | Current | Previous | Delta |');
  lines.push('| --- | --- | --- | --- |');
  for (const m of movers) {
    const deltaText = m.state === 'new' ? 'new' : m.delta > 0 ? `+${m.delta}` : `${m.delta}`;
    lines.push(`| ${escPipe(m.name)} | ${m.rank} | ${m.prev ?? '-'} | ${deltaText} |`);
  }
  lines.push('');
}

async function main() {
  const reports = await listReports();
  if (!reports.length) throw new Error(`No reports found in ${REPORT_DIR}`);

  const latest = reports[reports.length - 1];
  const prev = reports.length > 1 ? reports[reports.length - 2] : null;

  const latestJson = await readJsonIfExists(path.join(DATA_DIR, 'latest.json'));
  if (!latestJson?.datasets) throw new Error('data/latest.json with datasets is required');

  let datasets = dedupDatasets(latestJson.datasets).map((d) => ({ ...d, mediaType: d.mediaType || 'apps' }));
  datasets = applyFilters(datasets);
  datasets = sortDatasets(datasets);

  const countries = [...new Set(datasets.map((d) => String(d.country).toUpperCase()))];
  const mediaTypes = [...new Set(datasets.map((d) => String(d.mediaType).toLowerCase()))];
  const feeds = [...new Set(datasets.map((d) => String(d.feedType)))]
    .filter(Boolean)
    .sort();

  let prevRankMaps = new Map();
  if (prev) {
    const prevJson = await readJsonIfExists(path.join(DATA_DIR, `${prev.date}.json`));
    if (prevJson?.datasets) {
      const prevDatasets = sortDatasets(dedupDatasets(prevJson.datasets).map((d) => ({ ...d, mediaType: d.mediaType || 'apps' })));
      prevRankMaps = buildPrevRankMaps(prevDatasets);
    }
  }

  const home = [];
  home.push('# iOS Rank Wiki');
  home.push('');
  home.push('| Item | Value |');
  home.push('| --- | --- |');
  home.push(`| Latest update | ${latest.date} |`);
  home.push(`| Repository | [${process.env.GITHUB_REPOSITORY}](https://github.com/${process.env.GITHUB_REPOSITORY}) |`);
  home.push(`| Countries | ${countries.join(', ') || 'N/A'} |`);
  home.push(`| Media Types | ${mediaTypes.join(', ') || 'N/A'} |`);
  home.push(`| Feeds | ${feeds.join(', ') || 'N/A'} |`);
  home.push(`| Total datasets | ${datasets.length} |`);
  home.push('');

  home.push('## Quick Links');
  home.push('');
  home.push('- [Latest report](Latest.md)');
  home.push(`- [Daily-${latest.date}.md](Daily-${latest.date}.md)`);
  home.push('');

  home.push('## Navigation');
  home.push('');
  home.push('- [Recent reports](#recent-reports)');
  home.push('- [Top rankings](#top-10-snapshot)');
  for (const m of mediaTypes) {
    home.push(`- [${m.toUpperCase()}](#${slugify(m.toUpperCase())})`);
    for (const c of countries) {
      home.push(`  - [${c} ${m}](./${c}-${m}.md)`);
    }
  }
  home.push('');

  home.push('## Recent Reports');
  home.push('');
  home.push('| Date | Page |');
  home.push('| --- | --- |');
  for (const r of [...reports].reverse().slice(0, RECENT_LIMIT)) {
    home.push(`| ${r.date} | [Daily-${r.date}.md](Daily-${r.date}.md) |`);
  }
  home.push('');

  home.push('## Top 10 Snapshot');
  home.push('');

  for (const m of mediaTypes) {
    home.push(`### ${m.toUpperCase()}`);
    home.push('');
    for (const d of datasets.filter((x) => String(x.mediaType).toLowerCase() === m)) {
      const c = String(d.country).toUpperCase();
      home.push(`#### ${c} · ${d.feedType}`);
      home.push('');
      renderTopTable(home, d);
      const movers = computeMovers(d, prevRankMaps);
      renderMoverTable(home, movers, prev?.date || 'previous snapshot');
    }
  }

  const sidebar = [];
  sidebar.push('## Wiki Navigation');
  sidebar.push('');
  sidebar.push('- [Home](Home)');
  sidebar.push('- [Latest](Latest.md)');
  sidebar.push('');
  sidebar.push('### Country / Media');
  for (const c of countries) {
    for (const m of mediaTypes) {
      sidebar.push(`- [${c} ${m}](./${c}-${m}.md)`);
    }
  }
  sidebar.push('');
  sidebar.push('### Recent Reports');
  for (const r of [...reports].reverse().slice(0, Math.min(RECENT_LIMIT, 20))) {
    sidebar.push(`- [Daily-${r.date}.md](Daily-${r.date}.md)`);
  }

  await fs.writeFile(path.join(WIKI_DIR, 'Home.md'), `${home.join('\n')}\n`, 'utf8');
  await fs.writeFile(path.join(WIKI_DIR, '_Sidebar.md'), `${sidebar.join('\n')}\n`, 'utf8');

  for (const c of countries) {
    for (const m of mediaTypes) {
      const pageName = `${c}-${m}.md`;
      const page = [];
      page.push(`# ${c} ${m.toUpperCase()} Rankings`);
      page.push('');
      page.push('- [Home](Home)');
      page.push('- [Latest](Latest.md)');
      page.push('');
      const filtered = datasets.filter(
        (d) => String(d.country).toUpperCase() === c && String(d.mediaType).toLowerCase() === m
      );
      for (const d of filtered) {
        page.push(`## ${d.feedType}`);
        page.push('');
        renderTopTable(page, d);
        const movers = computeMovers(d, prevRankMaps);
        renderMoverTable(page, movers, prev?.date || 'previous snapshot');
      }
      await fs.writeFile(path.join(WIKI_DIR, pageName), `${page.join('\n')}\n`, 'utf8');
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
