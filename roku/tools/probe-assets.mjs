// Probe-build assets (M12 step 3, DEBUG builds only): `npm run build` and `npm run deploy` run this before bsc.
// Writes, under roku/out/probe-assets/ (gitignored, never committed):
//   sample-guide.xml.gz  a synthetic XMLTV guide, gzip-compressed to about 110 KB (the size of a small real
//                        guide), for probe d's inflate timing. Deterministic: a seeded generator, gzip mtime 0,
//                        fake ids and names under .example. Its inflated size is in build.json.
//   build.json           { built: <ISO time of this build>, sampleBytes, sampleCompressedBytes }; probe g uses
//                        `built` to tell whether the registry survived a re-sideload.
// bsconfig.json copies the folder into the package as pkg:/probes/; bsconfig.release.json leaves it out.
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'out', 'probe-assets');
const targetCompressed = 110 * 1024;

const words = ('news sports live game night show report weather world local city county state team season '
    + 'final round match cup league home away special classic best of the week today morning evening late '
    + 'update analysis preview review highlights college pro football basketball hockey baseball soccer '
    + 'golf tennis racing boxing studio talk magazine documentary series drama comedy family kids movie '
    + 'history science nature travel food cooking garden house market money business politics election').split(' ');

function makeRandom(seed) {
    let state = seed >>> 0;
    return () => {
        state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
        return state / 4294967296;
    };
}

function xmltvTime(ms) {
    const d = new Date(ms);
    const two = (n) => String(n).padStart(2, '0');
    return `${d.getUTCFullYear()}${two(d.getUTCMonth() + 1)}${two(d.getUTCDate())}`
        + `${two(d.getUTCHours())}${two(d.getUTCMinutes())}00 +0000`;
}

// A guide with `channels` channels and `perChannel` programmes each, from 2026-11-18 00:00 UTC.
function makeGuide(channels, perChannel) {
    const random = makeRandom(20261118);
    const pick = () => words[Math.floor(random() * words.length)];
    const phrase = (count) => Array.from({ length: count }, pick).join(' ');
    const title = (count) => phrase(count).replace(/\b\w/g, (c) => c.toUpperCase());
    const lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<tv generator-info-name="mmtvl-probe-synthetic">'];
    for (let c = 1; c <= channels; c++) {
        lines.push(`  <channel id="ch${c}.example">`, `    <display-name>Channel ${c}</display-name>`,
            `    <display-name>${c}.1</display-name>`, `    <icon src="https://img.example/ch${c}.png" />`, '  </channel>');
    }
    const durations = [30, 30, 30, 60, 60, 90, 120, 15];
    for (let c = 1; c <= channels; c++) {
        let time = Date.UTC(2026, 10, 18);
        for (let p = 0; p < perChannel; p++) {
            const minutes = durations[Math.floor(random() * durations.length)];
            const stop = time + minutes * 60000;
            lines.push(`  <programme start="${xmltvTime(time)}" stop="${xmltvTime(stop)}" channel="ch${c}.example">`,
                `    <title lang="en">${title(2 + Math.floor(random() * 3))}</title>`);
            if (random() < 0.6) lines.push(`    <sub-title lang="en">${title(2 + Math.floor(random() * 4))}</sub-title>`);
            lines.push(`    <desc lang="en">${phrase(40 + Math.floor(random() * 50))} &amp; ${phrase(5)}.</desc>`);
            if (random() < 0.3) lines.push(`    <credits><actor>${title(2)}</actor><actor>${title(2)}</actor></credits>`);
            lines.push(`    <category lang="en">${title(1)}</category>`, `    <category lang="en">${title(1)}</category>`,
                `    <icon src="https://img.example/p/${c}-${p}.jpg" />`);
            if (random() < 0.5) lines.push(`    <episode-num system="xmltv_ns">${Math.floor(random() * 9)}.${Math.floor(random() * 20)}.</episode-num>`);
            if (random() < 0.5) lines.push(`    <episode-num system="onscreen">S${1 + Math.floor(random() * 9)} E${1 + Math.floor(random() * 20)}</episode-num>`);
            lines.push(random() < 0.3 ? '    <new />' : '    <previously-shown />', '  </programme>');
            time = stop;
        }
    }
    lines.push('</tv>', '');
    return Buffer.from(lines.join('\n'), 'utf8');
}

const channels = 24;
let perChannel = 40;
let xml = makeGuide(channels, perChannel);
let gz = gzipSync(xml, { level: 9 });
// Scale the programme count to reach the target, twice (deterministic: same inputs, same steps).
for (let i = 0; i < 2; i++) {
    perChannel = Math.max(1, Math.round(perChannel * targetCompressed / gz.length));
    xml = makeGuide(channels, perChannel);
    gz = gzipSync(xml, { level: 9 });
}

mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'sample-guide.xml.gz'), gz);
writeFileSync(join(outDir, 'build.json'), JSON.stringify({
    built: new Date().toISOString(),
    sampleBytes: xml.length,
    sampleCompressedBytes: gz.length
}) + '\n');
console.log(`Probe assets: sample guide ${gz.length} bytes compressed, ${xml.length} inflated (${channels} channels × ${perChannel}).`);
