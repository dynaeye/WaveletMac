import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// Promote the exact approved local catalog without re-fetching or changing sources.
if (process.argv.includes('--sync-release')) {
  const dir = path.join(root, 'Shared/Resources');
  const catalog = JSON.parse(fs.readFileSync(path.join(dir, 'stations-candidates.json'), 'utf8'));
  assert.equal(catalog.schemaVersion, 1);
  assert.ok(catalog.stations.length > 0);
  assert.equal(new Set(catalog.stations.map(s => s.id)).size, catalog.stations.length);
  assert.ok(catalog.stations.every(s => s.streams.length > 0));
  fs.writeFileSync(path.join(dir, 'stations.json'), JSON.stringify(catalog, null, 2) + '\n');
  console.log(JSON.stringify({ release: catalog.stations.length, validation: catalog.validation }));
  process.exit(0);
}
const source = fs.readFileSync(path.resolve(root, '../radio-site/dist/stations.js'), 'utf8');
const raw = JSON.parse(source.match(/window\.STATIONS\s*=\s*(\[[\s\S]*\]);?\s*$/)[1]);
const meta = JSON.parse(source.match(/window\.CATALOG_META\s*=\s*([^\n]+);/)[1]);
const stations = raw.filter(s => s.status !== 'external').flatMap(s => {
  const seen = new Set();
  const streams = s.streams.filter(l => {
    const valid = l.web === true && l.testedAt && l.url.startsWith('https://') &&
      (l.type === 'hls' || ['aac', 'mp3'].includes(l.codec?.toLowerCase())) && !seen.has(l.url);
    if (valid) seen.add(l.url);
    return valid;
  }).map(l => ({ url: l.url, format: l.type === 'hls' ? 'hls' : l.codec.toLowerCase(), testedAt: l.testedAt }));
  return streams.length ? [{ id: s.id, name: s.name, region: s.region, group: s.group || '',
    city: s.city || '', category: s.category || '', language: s.language || '',
    aliases: [...new Set([...(s.aliases || []), s.mark, s.frequency].filter(Boolean).map(String))],
    official: s.official || '', source: s.source || '', streams }] : [];
});
assert.equal(new Set(stations.map(s => s.id)).size, stations.length);
// Release uses the same catalog as Debug; native validation remains a separate record.
const release = stations;
const dir = path.join(root, 'Shared/Resources');
fs.mkdirSync(dir, { recursive: true });
for (const [name, list, validation] of [['stations-candidates', stations, 'web-candidate'], ['stations', release, 'web-candidate']]) {
  fs.writeFileSync(path.join(dir, name + '.json'), JSON.stringify({ schemaVersion: 1, sourceUpdatedAt: meta.updatedAt, validation, stations: list }, null, 2) + '\n');
}
console.log(JSON.stringify({ source: raw.length, candidates: stations.length, streams: stations.reduce((n,s) => n+s.streams.length,0), release: release.length,
  excludedWebStations: raw.filter(s => s.streams.some(l => l.web) && !stations.some(t => t.id === s.id)).map(s => ({ id: s.id, name: s.name, formats: s.streams.map(l => l.codec) })) }, null, 2));
