// M14: the version helpers (tools/version.mjs). Run with `npm run test:tools`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
    buildSourceRefusal, githubRepo, identEmail, isPNG, keepNewest, neutralMentions, newestZip, parseSourceRecord, parseVersion, releaseNotes,
    releaseTitle, sourceRecord, tagName, withBuild, zipName
} from './version.mjs';

const manifestPath = join(dirname(fileURLToPath(import.meta.url)), '..', 'manifest');
const sample = [
    'title=MMTVL Live TV',
    'major_version=0',
    'minor_version=1',
    'build_version=1',
    '',
    '# DEBUG builds print info logs.',
    'bs_const=DEBUG=true',
    ''
].join('\n');

// The build number isn't pinned: `npm run nightly` bumps it before this gate runs (L2).
test('parseVersion reads the real manifest as 0.1 with a build number of at least 1', () => {
    const { major, minor, build } = parseVersion(readFileSync(manifestPath, 'utf8'));
    assert.deepEqual({ major, minor }, { major: 0, minor: 1 });
    assert.ok(Number.isSafeInteger(build) && build >= 1, `build ${build}`);
});

test('parseVersion throws naming the key for a missing or bad line', () => {
    const cases = [
        [sample.replace('build_version=1\n', ''), /build_version/],
        [sample.replace('build_version=1', 'build_version=abc'), /build_version/],
        [sample.replace('build_version=1', 'build_version=-1'), /build_version/],
        [sample.replace('build_version=1', 'build_version='), /build_version/],
        [sample.replace('minor_version=1\n', ''), /minor_version/]
    ];
    for (const [text, key] of cases) {
        assert.throws(() => parseVersion(text), key);
    }
});

test('parseVersion reads build_version=00150 as 150', () => {
    assert.equal(parseVersion(sample.replace('build_version=1', 'build_version=00150')).build, 150);
});

test('parseVersion reads a CRLF manifest', () => {
    assert.deepEqual(parseVersion(sample.replaceAll('\n', '\r\n')), { major: 0, minor: 1, build: 1 });
});

test('withBuild changes only the build_version line', () => {
    const changed = withBuild(sample, 2);
    assert.equal(changed, sample.replace('build_version=1', 'build_version=2'));
    assert.match(changed, /^bs_const=DEBUG=true$/m);
    assert.match(changed, /^# DEBUG builds print info logs\.$/m);
    assert.ok(changed.endsWith('bs_const=DEBUG=true\n'));
    assert.deepEqual(parseVersion(changed), { major: 0, minor: 1, build: 2 });
});

test('withBuild keeps CRLF line endings and no trailing newline as they are', () => {
    const crlf = sample.replaceAll('\n', '\r\n');
    assert.equal(withBuild(crlf, 12), crlf.replace('build_version=1\r\n', 'build_version=12\r\n'));
    const noTrailing = sample.trimEnd();
    assert.equal(withBuild(noTrailing, 3), noTrailing.replace('build_version=1', 'build_version=3'));
});

test('withBuild keeps the real manifest byte for byte apart from the build line', () => {
    const real = readFileSync(manifestPath, 'utf8');
    const changed = withBuild(real, 7);
    const before = real.split('\n');
    const after = changed.split('\n');
    assert.equal(after.length, before.length);
    for (let i = 0; i < before.length; i++) {
        if (before[i].startsWith('build_version=')) {
            assert.equal(after[i], 'build_version=7');
        } else {
            assert.equal(after[i], before[i]);
        }
    }
});

test('withBuild throws for a manifest without build_version, or a bad number', () => {
    assert.throws(() => withBuild(sample.replace('build_version=1\n', ''), 2), /build_version/);
    assert.throws(() => withBuild(sample, -1));
    assert.throws(() => withBuild(sample, 1.5));
});

test('zipName, tagName and releaseTitle give the exact strings', () => {
    const nightly = { major: 0, minor: 1, build: 2 };
    const stable = { major: 1, minor: 0, build: 9 };
    assert.equal(zipName(nightly), 'MMTVL-Live-TV-Roku-0.1-build2.zip');
    assert.equal(tagName(nightly), 'roku-v0.1-build2');
    assert.equal(releaseTitle(nightly), 'MMTVL Live TV for Roku 0.1 build 2 (nightly, WIP)');
    assert.equal(releaseTitle(nightly, { stable: false }), 'MMTVL Live TV for Roku 0.1 build 2 (nightly, WIP)');
    assert.equal(zipName(stable), 'MMTVL-Live-TV-Roku-1.0-build9.zip');
    assert.equal(tagName(stable), 'roku-v1.0-build9');
    assert.equal(releaseTitle(stable, { stable: true }), 'MMTVL Live TV for Roku 1.0 build 9');
});

test('keepNewest returns only the zips past the newest n, by build number', () => {
    const names = [
        'MMTVL-Live-TV-Roku-0.1-build2.zip',
        'MMTVL-Live-TV-Roku-0.1-build10.zip',
        'MMTVL-Live-TV-Roku-0.1-build3.zip',
        'MMTVL-Live-TV-Roku-0.1-build4.zip',
        'MMTVL-Live-TV-Roku-0.1-build2.zip.sha256',
        'mmtvl-live-tv.zip'
    ];
    assert.deepEqual(keepNewest(names, 3), ['MMTVL-Live-TV-Roku-0.1-build2.zip']);
    // By number, not text: build10 is the newest, so with n = 1, 4, 3 and 2 go.
    assert.deepEqual(keepNewest(names, 1), [
        'MMTVL-Live-TV-Roku-0.1-build4.zip',
        'MMTVL-Live-TV-Roku-0.1-build3.zip',
        'MMTVL-Live-TV-Roku-0.1-build2.zip'
    ]);
    assert.deepEqual(keepNewest(names, 4), []);
    assert.deepEqual(keepNewest(['mmtvl-live-tv.zip', 'mmtvl-live-tv-release.zip', 'notes.txt'], 0), []);
});

test('newestZip picks the highest build number, not the last name in text order', () => {
    const names = [
        'MMTVL-Live-TV-Roku-0.1-build9.zip',
        'MMTVL-Live-TV-Roku-0.1-build10.zip',
        'MMTVL-Live-TV-Roku-0.1-build10.zip.sha256',
        'MMTVL-Live-TV-Roku-0.1-build4.zip',
        'mmtvl-live-tv-release.zip'
    ];
    assert.equal(newestZip(names), 'MMTVL-Live-TV-Roku-0.1-build10.zip');
    assert.equal(newestZip(['mmtvl-live-tv.zip', 'MMTVL-Live-TV-Roku-0.1-build2.zip.sha256', '.DS_Store']), null);
    assert.equal(newestZip([]), null);
});

const nightlyNotes = releaseNotes({
    v: { major: 0, minor: 1, build: 2 },
    sha256: 'a'.repeat(64),
    zip: 'MMTVL-Live-TV-Roku-0.1-build2.zip',
    changes: ''
});
const stableNotes = releaseNotes({
    v: { major: 1, minor: 0, build: 9 },
    sha256: 'b'.repeat(64),
    zip: 'MMTVL-Live-TV-Roku-1.0-build9.zip',
    changes: '- Roku: one change\n- Roku: another\n',
    stable: true
});

test('releaseNotes for a nightly: the WIP box, the zip, the SHA-256 and "First Roku nightly."', () => {
    assert.ok(nightlyNotes.startsWith('# MMTVL Live TV for Roku 0.1 build 2 (nightly)\n'));
    assert.match(nightlyNotes, /^> \*\*Nightly, work in progress\.\*\*/m);
    assert.match(nightlyNotes, /`MMTVL-Live-TV-Roku-0\.1-build2\.zip`/);
    assert.ok(nightlyNotes.includes('`' + 'a'.repeat(64) + '`'));
    assert.match(nightlyNotes, /^- First Roku nightly\.$/m);
    assert.match(nightlyNotes, /Settings → About should say "Version 0\.1 Build 2"\./);
    assert.match(nightlyNotes, /^## Upgrading$/m);
});

test('releaseNotes for a stable release: no "nightly" and no WIP box', () => {
    assert.ok(stableNotes.startsWith('# MMTVL Live TV for Roku 1.0 build 9\n'));
    assert.doesNotMatch(stableNotes, /nightly/i);
    assert.doesNotMatch(stableNotes, /work in progress|^>/im);
    assert.match(stableNotes, /^## Install the release \(sideload\)$/m);
    assert.match(stableNotes, /^- Roku: one change\n- Roku: another\n\n## Upgrading$/m);
    assert.ok(stableNotes.includes('`' + 'b'.repeat(64) + '`'));
    const noChanges = releaseNotes({ v: { major: 1, minor: 0, build: 9 }, sha256: 'c', zip: 'z.zip', changes: [], stable: true });
    assert.match(noChanges, /^- First Roku release\.$/m);
});

test('releaseNotes takes the changes as an array of lines too', () => {
    const notes = releaseNotes({ v: { major: 0, minor: 1, build: 3 }, sha256: 'd', zip: 'z.zip', changes: ['- One', '- Two'] });
    assert.match(notes, /^## Changes since the last Roku build\n- One\n- Two\n$/m);
});

test('releaseNotes has no http:// but the placeholder address', () => {
    for (const notes of [nightlyNotes, stableNotes]) {
        const urls = notes.match(/http:\/\/[^\s`]*/g) ?? [];
        assert.deepEqual(urls, ['http://<your']);
        assert.ok(notes.includes("http://<your Roku's address>/"));
        assert.doesNotMatch(notes, /https:\/\//);
    }
});

// Security L5: a commit subject can't notify anyone from the release notes.
test('neutralMentions puts @mentions outside code spans in code spans, and leaves emails and code alone', () => {
    assert.equal(neutralMentions('- Fix for @someone and @org/team'), '- Fix for `@someone` and `@org/team`');
    assert.equal(neutralMentions('@lead: thanks'), '`@lead`: thanks');
    assert.equal(neutralMentions('- Bump `@types/node`, mail a@b.example'), '- Bump `@types/node`, mail a@b.example');
    assert.equal(neutralMentions('- `npm i @x` then (@y)'), '- `npm i @x` then (`@y`)');
    assert.equal(neutralMentions('- One @a\n- Two @b'), '- One `@a`\n- Two `@b`');
    assert.equal(neutralMentions('- No mention @ all'), '- No mention @ all');
});

test('releaseNotes neutralises mentions in the changes', () => {
    const notes = releaseNotes({ v: { major: 0, minor: 1, build: 3 }, sha256: 'd', zip: 'z.zip', changes: '- Thanks @helper' });
    assert.match(notes, /^- Thanks `@helper`$/m);
    assert.doesNotMatch(notes, /(^|[^`])@helper/m);
});

// Security 1: the .source sidecar ties a zip to the commit it was built from (and, N2, to the zip itself).
const commitX = 'a'.repeat(40);
const zipSha = 'c'.repeat(64);
const record = (clean) => sourceRecord({ commit: commitX, clean, sha256: zipSha });
test('sourceRecord and parseSourceRecord round-trip, and parseSourceRecord rejects anything else', () => {
    assert.deepEqual(parseSourceRecord(record(true)), { commit: commitX, clean: true, sha256: zipSha });
    assert.deepEqual(parseSourceRecord(record(false)), { commit: commitX, clean: false, sha256: zipSha });
    const bad = ['', 'not json', '{}', 'null', '{"commit":"abc","clean":true}', `{"commit":"${commitX}","clean":"yes","sha256":"${zipSha}"}`,
        `{"commit":"${commitX}","clean":true}`, `{"commit":"${commitX}","clean":true,"sha256":"abc"}`];
    for (const text of bad) {
        assert.throws(() => parseSourceRecord(text), undefined, text);
    }
});

test('buildSourceRefusal refuses a dry run built from a dirty tree, before comparing anything', () => {
    let compared = false;
    const refusal = buildSourceRefusal(record(false), () => {
        compared = true;
        return 0;
    }, zipSha);
    assert.match(refusal, /uncommitted changes \(a dry run\) at aaaaaaaaa/);
    assert.equal(compared, false);
});

test('buildSourceRefusal refuses a zip built at commit X when HEAD differs from X outside roku/manifest', () => {
    const asked = [];
    const refusal = buildSourceRefusal(record(true), (commit) => {
        asked.push(commit);
        return 1;
    }, zipSha);
    assert.match(refusal, /built from aaaaaaaaa, and HEAD differs from it outside roku\/manifest/);
    assert.deepEqual(asked, [commitX]);
    assert.match(buildSourceRefusal(record(true), () => 128, zipSha), /couldn't be compared/);
});

test('buildSourceRefusal passes a clean build of HEAD, and refuses a missing or bad .source', () => {
    assert.equal(buildSourceRefusal(record(true), () => 0, zipSha), null);
    assert.equal(buildSourceRefusal(record(true), () => 0, zipSha.toUpperCase()), null);
    assert.match(buildSourceRefusal(null, () => 0, zipSha), /has no \.source file/);
    assert.match(buildSourceRefusal('{"clean":true}', () => 0, zipSha), /has a \.source file that/);
});

// Security N2: a .source is bound to its zip.
test('buildSourceRefusal refuses a .source made for another zip, before comparing anything', () => {
    let compared = false;
    const refusal = buildSourceRefusal(record(true), () => {
        compared = true;
        return 0;
    }, 'd'.repeat(64));
    assert.match(refusal, /made for another zip/);
    assert.equal(compared, false);
    assert.match(buildSourceRefusal(record(true), () => 0, undefined), /made for another zip/);
});

// Security N5: an image by its bytes, not its name.
test('isPNG checks the PNG signature', () => {
    assert.equal(isPNG(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00])), true);
    assert.equal(isPNG(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a])), false);
    assert.equal(isPNG(Buffer.from('url = "http://leak-test.invalid/"')), false);
    assert.equal(isPNG(Buffer.alloc(0)), false);
    assert.equal(isPNG(null), false);
});

// Security L3.
test('githubRepo reads owner/repo from GitHub URLs only', () => {
    assert.equal(githubRepo('https://github.com/owner/repo.git'), 'owner/repo');
    assert.equal(githubRepo('https://github.com/owner/repo'), 'owner/repo');
    assert.equal(githubRepo('git@github.com:owner/my.repo.git'), 'owner/my.repo');
    assert.equal(githubRepo('ssh://git@github.com/owner/repo.git'), 'owner/repo');
    for (const other of ['/tmp/origin.git', 'https://github.com.evil.example/owner/repo', 'https://example.com/github.com/owner/repo',
        'https://github.com/owner', '']) {
        assert.equal(githubRepo(other), null, other);
    }
});

// Security L4.
test('identEmail reads the email of a committer ident', () => {
    assert.equal(identEmail('A Name <1+name@users.noreply.github.com> 1700000000 +0000'), '1+name@users.noreply.github.com');
    assert.equal(identEmail('no email here'), null);
});
