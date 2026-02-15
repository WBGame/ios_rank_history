import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const DATA_DIR = process.env.DATA_DIR || 'data';
const REPORT_DIR = process.env.REPORT_DIR || 'reports';
const today = new Date().toISOString().slice(0, 10);

async function main() {
  const latestFile = join(DATA_DIR, 'latest.json');
  const reportFile = join(REPORT_DIR, `daily-${today}.md`);

  const raw = await readFile(latestFile, 'utf8');
  const payload = JSON.parse(raw);

  await mkdir(REPORT_DIR, { recursive: true });

  const lines = [];
  lines.push(`# iOS Rank Daily Report (${payload.date})`);
  lines.push('');
  lines.push(`- Country: ${payload.country}`);
  lines.push(`- Feed: ${payload.feedType}`);
  lines.push(`- Total: ${payload.total}`);
  lines.push(`- Source: ${payload.source}`);
  lines.push('');
  lines.push('## Top 20');
  lines.push('');
  lines.push('| Rank | Name | Artist | App ID |');
  lines.push('| --- | --- | --- | --- |');

  for (const item of payload.items.slice(0, 20)) {
    lines.push(`| ${item.rank} | ${item.name} | ${item.artistName} | ${item.id} |`);
  }

  lines.push('');
  await writeFile(reportFile, `${lines.join('\n')}\n`, 'utf8');
  console.log(`report generated: ${reportFile}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
