import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const DATA_DIR = process.env.DATA_DIR || 'data';
const REPORT_DIR = process.env.REPORT_DIR || 'reports';
const TOP_N = Number.parseInt(process.env.REPORT_TOP_N || '20', 10);
const today = new Date().toISOString().slice(0, 10);

function renderSection(lines, dataset) {
  lines.push(
    `## ${dataset.country.toUpperCase()} ${dataset.mediaType} ${dataset.feedType} Top ${Math.min(TOP_N, dataset.items.length)}`
  );
  lines.push('');
  lines.push(`- Total: ${dataset.total}`);
  lines.push(`- Source: ${dataset.source}`);
  lines.push('');
  lines.push('| Rank | Name | Artist | App ID |');
  lines.push('| --- | --- | --- | --- |');

  for (const item of dataset.items.slice(0, TOP_N)) {
    lines.push(`| ${item.rank} | ${item.name} | ${item.artistName} | ${item.id} |`);
  }

  lines.push('');
}

async function main() {
  const latestFile = join(DATA_DIR, 'latest.json');
  const reportFile = join(REPORT_DIR, `daily-${today}.md`);

  const raw = await readFile(latestFile, 'utf8');
  const payload = JSON.parse(raw);

  await mkdir(REPORT_DIR, { recursive: true });

  const datasets = Array.isArray(payload.datasets) ? payload.datasets : [payload];
  datasets.sort((a, b) => {
    const c = String(a.country).localeCompare(String(b.country));
    if (c !== 0) return c;
    return String(a.feedType).localeCompare(String(b.feedType));
  });

  const countries = [...new Set(datasets.map((d) => String(d.country).toUpperCase()))];
  const mediaTypes = [...new Set(datasets.map((d) => String(d.mediaType || 'apps')))];
  const feeds = [...new Set(datasets.map((d) => d.feedType))];

  const lines = [];
  lines.push(`# iOS Rank Daily Report (${payload.date || today})`);
  lines.push('');
  lines.push(`- Countries: ${countries.join(', ')}`);
  lines.push(`- Media Types: ${mediaTypes.join(', ')}`);
  lines.push(`- Feeds: ${feeds.join(', ')}`);
  lines.push(`- Total datasets: ${datasets.length}`);
  lines.push('');

  for (const dataset of datasets) {
    renderSection(lines, dataset);
  }

  await writeFile(reportFile, `${lines.join('\n')}\n`, 'utf8');
  console.log(`report generated: ${reportFile}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
