// The Roku app's version (M14). roku/manifest's major_version, minor_version and build_version are the only
// version source (L1); the build number goes up by 1 for every nightly and is never reset or reused (L2).
// Pure helpers: no I/O beyond what's passed in. Tested by version.test.mjs (`npm run test:tools`).

const versionKeys = ['major_version', 'minor_version', 'build_version'];
const zipPattern = /^MMTVL-Live-TV-Roku-(\d+)\.(\d+)-build(\d+)\.zip$/;

function manifestValue(manifestText, key) {
    const match = new RegExp(`^${key}=([^\\r\\n]*)`, 'm').exec(manifestText);
    if (!match) {
        throw new Error(`The manifest has no ${key} line.`);
    }
    const value = match[1].trim();
    if (!/^\d+$/.test(value)) {
        throw new Error(`The manifest's ${key} isn't a whole number ≥ 0.`);
    }
    return Number.parseInt(value, 10);
}

// → { major, minor, build }; throws naming the key when a line is missing or not an integer ≥ 0.
export function parseVersion(manifestText) {
    const [major, minor, build] = versionKeys.map((key) => manifestValue(manifestText, key));
    return { major, minor, build };
}

// → manifestText with only the build_version line's value changed to n; everything else byte for byte.
export function withBuild(manifestText, n) {
    if (!Number.isSafeInteger(n) || n < 0) {
        throw new Error(`The build number must be a whole number ≥ 0, not ${n}.`);
    }
    const line = /^build_version=[^\r\n]*/m;
    if (!line.test(manifestText)) {
        throw new Error('The manifest has no build_version line.');
    }
    return manifestText.replace(line, `build_version=${n}`);
}

const versionText = ({ major, minor }) => `${major}.${minor}`;

// → "MMTVL-Live-TV-Roku-0.1-build2.zip" (L9)
export function zipName(v) {
    return `MMTVL-Live-TV-Roku-${versionText(v)}-build${v.build}.zip`;
}

// → "roku-v0.1-build2" (L4)
export function tagName(v) {
    return `roku-v${versionText(v)}-build${v.build}`;
}

// → "MMTVL Live TV for Roku 0.1 build 2 (nightly, WIP)", or with stable "MMTVL Live TV for Roku 1.0 build 9" (L3, L4)
export function releaseTitle(v, { stable = false } = {}) {
    const title = `MMTVL Live TV for Roku ${versionText(v)} build ${v.build}`;
    return stable ? title : `${title} (nightly, WIP)`;
}

// → the names to delete: all but the n highest build numbers among the names that match zipName's pattern.
// Other names (a zip's .sha256, the build's own zips) are never returned; the caller removes each zip's .sha256.
export function keepNewest(fileNames, n) {
    return nightlyZipsNewestFirst(fileNames).slice(Math.max(0, n));
}

// → the name with the highest build number among the names that match zipName's pattern, or null (deploy:nightly).
export function newestZip(fileNames) {
    return nightlyZipsNewestFirst(fileNames)[0] ?? null;
}

// The names that match zipName's pattern, highest build number first (by number, not text).
function nightlyZipsNewestFirst(fileNames) {
    return fileNames
        .map((name) => ({ name, match: zipPattern.exec(name) }))
        .filter(({ match }) => match)
        .map(({ name, match }) => ({ name, build: Number.parseInt(match[3], 10) }))
        .sort((a, b) => b.build - a.build)
        .map(({ name }) => name);
}

// → text with every @mention outside a `code span` put in one, so a commit subject in the release notes can't notify
// anyone (security L5). An @ after a letter or digit (an email address) is left alone.
export function neutralMentions(text) {
    return String(text ?? '').split('\n').map((line) => line
        .split(/(`[^`\n]*`)/)
        .map((part, index) => (index % 2 === 1
            ? part
            : part.replace(/(^|[^\w`])@([A-Za-z0-9][\w-]*(?:\/[\w.-]+)?)/g, '$1`@$2`')))
        .join(''))
        .join('\n');
}

// The `<zipName>.source` sidecar (security 1): the commit a nightly was built from (HEAD before the bump) and whether
// the tree was clean then, and (security N2) the SHA-256 of the zip it describes, so it can't be paired with another
// zip. publish:nightly publishes a zip only from a clean build of HEAD's tree.
export function sourceRecord({ commit, clean, sha256 }) {
    return `${JSON.stringify({ commit, clean: clean === true, sha256 })}\n`;
}

// → { commit, clean, sha256 }; throws with a one-line reason for anything else.
export function parseSourceRecord(text) {
    let record;
    try {
        record = JSON.parse(text);
    } catch {
        throw new Error('isn\'t JSON');
    }
    if (!record || typeof record !== 'object' || !/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(record.commit ?? '')
        || typeof record.clean !== 'boolean' || !/^[0-9a-f]{64}$/.test(record.sha256 ?? '')) {
        throw new Error('doesn\'t hold a commit, clean: true or false, and the zip\'s SHA-256');
    }
    return { commit: record.commit, clean: record.clean, sha256: record.sha256 };
}

// → why the zip described by recordText can't be published, or null. zipSha256 is the zip's own SHA-256 (N2);
// diffStatus(commit) is the exit status of `git diff --quiet <commit> HEAD -- . ':!roku/manifest'` (0: HEAD differs
// from it only in roku/manifest, 1: elsewhere too).
export function buildSourceRefusal(recordText, diffStatus, zipSha256) {
    if (recordText === null || recordText === undefined) {
        return 'has no .source file, so it can\'t be tied to a commit: run npm run nightly on a clean master';
    }
    let record;
    try {
        record = parseSourceRecord(recordText);
    } catch (error) {
        return `has a .source file that ${error.message}`;
    }
    if (record.sha256 !== String(zipSha256 ?? '').toLowerCase()) {
        return 'has a .source file made for another zip (its SHA-256 differs)';
    }
    if (!record.clean) {
        return `was built from a tree with uncommitted changes (a dry run) at ${record.commit.slice(0, 9)}`;
    }
    const status = diffStatus(record.commit);
    if (status === 1) {
        return `was built from ${record.commit.slice(0, 9)}, and HEAD differs from it outside roku/manifest`;
    }
    if (status !== 0) {
        return `was built from ${record.commit.slice(0, 9)}, which couldn't be compared with HEAD (is it in this repo?)`;
    }
    return null;
}

// → whether bytes (a Buffer or Uint8Array) start with the PNG signature (security N5: a file is an image by its
// content, not its name).
const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
export function isPNG(bytes) {
    return Boolean(bytes) && bytes.length >= pngSignature.length && pngSignature.every((byte, index) => bytes[index] === byte);
}

// → "owner/repo" for a GitHub remote URL (https, ssh or scp form), or null (security L3).
export function githubRepo(url) {
    const match = /^(?:https:\/\/(?:[^@/]+@)?github\.com\/|ssh:\/\/git@github\.com\/|git@github\.com:)([\w.-]+)\/([\w.-]+?)(?:\.git)?\/?$/i
        .exec(String(url ?? '').trim());
    return match ? `${match[1]}/${match[2]}` : null;
}

// → the email of a `git var GIT_COMMITTER_IDENT` line ("Name <email> 1700000000 +0000"), or null (security L4).
export function identEmail(ident) {
    const match = /<([^<>\s]+)>/.exec(String(ident ?? ''));
    return match ? match[1] : null;
}

// → the release's Markdown body. Every value comes from the repo: no hosts, addresses or provider names.
// changes: the `git log --format='- %s'` lines (a string or an array of lines); empty means the first build.
// Mentions in them are put in code spans (neutralMentions).
export function releaseNotes({ v, sha256, zip, changes, stable = false }) {
    const version = versionText(v);
    const changeLines = neutralMentions(Array.isArray(changes) ? changes.join('\n') : (changes ?? '')).trim();
    const lines = [`# MMTVL Live TV for Roku ${version} build ${v.build}${stable ? '' : ' (nightly)'}`, ''];
    if (!stable) {
        lines.push(
            '> **Nightly, work in progress.** Built off-device; not yet verified on a Roku (see roku/README.md, "Not verified on a Roku yet"). Not MMTVL for the Mac: that\'s the "Latest" release.',
            ''
        );
    }
    lines.push(
        stable ? '## Install the release (sideload)' : '## Install (sideload)',
        '1. Put the Roku in developer mode (roku/README.md, "Developer mode and sideloading").',
        `2. Download \`${zip}\` below; don't unzip it.`,
        '3. Open `http://<your Roku\'s address>/`, sign in as `rokudev`, and upload the zip on the installer page (Replace).',
        `4. Settings → About should say "Version ${version} Build ${v.build}".`,
        '',
        'SHA-256 of the zip:',
        `\`${sha256}\``,
        '',
        '## Changes since the last Roku build',
        changeLines || (stable ? '- First Roku release.' : '- First Roku nightly.'),
        '',
        '## Upgrading',
        'Uploading replaces the installed build. If your settings are gone afterwards, run the migration again (`python3 -I scripts/roku-export-settings.py`, roku/README.md).',
        ''
    );
    return lines.join('\n');
}
