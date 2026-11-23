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

// → the release's Markdown body. Every value comes from the repo: no hosts, addresses or provider names.
// changes: the `git log --format='- %s'` lines (a string or an array of lines); empty means the first build.
export function releaseNotes({ v, sha256, zip, changes, stable = false }) {
    const version = versionText(v);
    const changeLines = (Array.isArray(changes) ? changes.join('\n') : (changes ?? '')).trim();
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
