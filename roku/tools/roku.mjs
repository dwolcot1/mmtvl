// The device scripts (M12 L1): `npm run deploy | test | console` and (M14) `npm run deploy:nightly`, and `npm run test:local`,
// `npm run build:release` and (M14) `npm run version | nightly`, which need no device, and (M14) `npm run publish:nightly`,
// which tags and publishes on GitHub (only after the user's yes) and never reads roku/.env.
// The Roku's address and developer password come only from roku/.env (gitignored).
// Never print the password.
import { copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { basename, dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseEnv } from 'node:util';
import {
    buildSourceRefusal, githubRepo, identEmail, isPNG, keepNewest, newestZip, parseVersion, releaseNotes, releaseTitle, sourceRecord,
    tagName, withBuild, zipName
} from './version.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const bin = (name) => join(root, 'node_modules', '.bin', name);

function fail(message) {
    console.error(message);
    process.exit(1);
}

function loadDevice() {
    const envPath = join(root, '.env');
    if (!existsSync(envPath)) {
        fail('roku/.env is missing: copy .env.example to .env and fill in ROKU_HOST and ROKU_DEV_PASSWORD.');
    }
    const env = parseEnv(readFileSync(envPath, 'utf8'));
    const host = (env.ROKU_HOST ?? '').trim();
    const password = env.ROKU_DEV_PASSWORD ?? '';
    if (!host) {
        fail('roku/.env has no ROKU_HOST: set it to the Roku\'s LAN address.');
    }
    if (!password) {
        fail('roku/.env has no ROKU_DEV_PASSWORD: set it to the developer installer password.');
    }
    return { host, password };
}

function run(command, args, extraEnv = {}) {
    const result = spawnSync(command, args, { cwd: root, stdio: 'inherit', env: { ...process.env, ...extraEnv } });
    if (result.error) {
        fail(`Couldn't run ${command}: ${result.error.message}`);
    }
    return result.status ?? 1;
}

async function deploy() {
    const { host, password } = loadDevice();
    if (run(process.execPath, [join('tools', 'probe-assets.mjs')]) !== 0
        || run(bin('bsc'), ['--project', 'bsconfig.json']) !== 0) {
        fail('The build failed; nothing was deployed.');
    }
    const { rokuDeploy } = await import('roku-deploy');
    try {
        await rokuDeploy.publish({ host, password, outDir: 'out', outFile: 'mmtvl-live-tv.zip' });
        console.log(`Deployed out/mmtvl-live-tv.zip to ${host}.`);
    } catch (error) {
        fail(`Deploy to ${host} failed: ${error.message}`);
    }
}

function test() {
    // M14: Rooibos sideloads through its own roku-deploy, whose sideload() deletes the installed dev app first
    // (deleteDevChannel defaults to true, and Rooibos passes no option), which clears the app's registry.
    // Printed first, on stderr like loadDevice's lines, so it comes before them; no prompt (npm scripts aren't interactive).
    console.warn('npm test installs the test app and deletes the installed MMTVL Live TV first, which erases its settings (Rooibos\'s roku-deploy deletes the dev app). Afterwards: npm run deploy:nightly, then run the migration again.');
    const { host, password } = loadDevice();
    // Rooibos builds with bsconfig.test.json, sideloads, then reads the results from port 8085.
    process.exit(run(bin('rooibos'), ['--project', 'bsconfig.test.json', '--host', host], { ROKU_PASSWORD: password }));
}

function console8085() {
    const { host } = loadDevice();
    process.exit(run('nc', [host, '8085']));
}

// The off-device tests (M12, Deviations 2026-11-18): bsc compiles source/lib and tests/local into
// out/local-staging; every `sub test_<name>(t)` in `namespace <Suite>Tests` of tests/local/<Suite>.test.bs
// is listed in a generated Main, and brs-node runs them all. Exits non-zero on a compile error, a crash,
// any FAIL line, a missing summary or no tests at all.
function testLocal() {
    const staging = join(root, 'out', 'local-staging');
    if (run(bin('bsc'), ['--project', 'bsconfig.local.json']) !== 0) {
        fail('test:local: the build failed.');
    }
    const testsDir = join(staging, 'source', 'localtests');
    const suites = [];
    for (const file of readdirSync(testsDir).filter((name) => name.endsWith('.test.brs')).sort()) {
        const suite = file.slice(0, -'.test.brs'.length);
        const text = readFileSync(join(testsDir, file), 'utf8');
        const tests = [...text.matchAll(/^\s*(?:sub|function)\s+(\w+?_test_(\w+))\s*\(/gim)]
            .map((match) => ({ fn: match[1], name: match[2] }));
        if (tests.length > 0) {
            suites.push({ suite, tests });
        }
    }
    const count = suites.reduce((total, s) => total + s.tests.length, 0);
    if (count === 0) {
        fail('test:local: no tests found in tests/local/*.test.bs.');
    }
    const quote = (text) => '"' + text.replaceAll('"', '""') + '"';
    const lines = ["' Generated by tools/roku.mjs test:local; not committed.", 'sub Main()', '    suites = []'];
    for (const { suite, tests } of suites) {
        lines.push(`    suites.Push({ name: ${quote(suite)}, tests: [`);
        for (const { fn, name } of tests) {
            lines.push(`        { name: ${quote(name)}, fn: ${fn} },`);
        }
        lines.push('    ] })');
    }
    lines.push('    LocalTest_runSuites(suites)', 'end sub', '');
    const mainPath = join(staging, 'source', 'main.brs');
    writeFileSync(mainPath, lines.join('\n'));

    const files = [mainPath];
    const collect = (dir) => {
        for (const entry of readdirSync(dir, { withFileTypes: true })) {
            const path = join(dir, entry.name);
            if (entry.isDirectory()) {
                collect(path);
            } else if (entry.name.endsWith('.brs') && path !== mainPath) {
                files.push(path);
            }
        }
    };
    collect(join(staging, 'source'));

    // -n: no SceneGraph (pure logic only); -c 0: no colours; -r: pkg:/ is the staging folder, so tests read the
    // shared fixtures as pkg:/fixtures/<name> (staged by bsconfig.local.json only, never in the app's zips).
    // stdin is closed so a STOP can't wait for input.
    // With -r, brs-cli takes the files relative to that root.
    const relativeFiles = files.map((file) => relative(staging, file));
    const result = spawnSync(bin('brs-cli'), ['-n', '-c', '0', '-r', staging, ...relativeFiles], {
        cwd: staging,
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe']
    });
    process.stdout.write(result.stdout ?? '');
    process.stderr.write(result.stderr ?? '');
    if (result.error) {
        fail(`test:local: couldn't run brs-cli: ${result.error.message}`);
    }
    const summary = /^LOCAL TESTS: (\d+) passed, (\d+) failed$/m.exec(result.stdout ?? '');
    if (result.status !== 0 || !summary) {
        fail(`test:local: brs-node stopped before the summary (exit ${result.status}).`);
    }
    const failed = Number(summary[2]);
    const passed = Number(summary[1]);
    if (failed > 0 || passed !== count) {
        fail(`test:local: ${failed} failed, ${passed} of ${count} passed.`);
    }
}

// The release build (M12 step 3): bsconfig.release.json leaves out components/probes and the probe assets and
// compiles with bs_const DEBUG=false (bsc removes every #if DEBUG block). The staged manifest's bs_const line is
// set to DEBUG=false too, then the staging folder is checked (both team catalogs under data/; no probes folder, no
// file or text naming a probe; step 22: no DEBUG memory console line) before it is zipped to out/mmtvl-live-tv-release.zip. Signed packaging is a later step.
async function buildRelease() {
    const staging = join(root, 'out', 'release-staging');
    rmSync(staging, { recursive: true, force: true });
    if (run(bin('bsc'), ['--project', 'bsconfig.release.json']) !== 0) {
        fail('build:release: the build failed.');
    }
    const manifestPath = join(staging, 'manifest');
    const manifest = readFileSync(manifestPath, 'utf8');
    if (!/^bs_const=.*$/m.test(manifest)) {
        fail('build:release: the manifest has no bs_const line.');
    }
    writeFileSync(manifestPath, manifest.replace(/^bs_const=.*$/m, 'bs_const=DEBUG=false'));

    const files = [];
    const collect = (dir, prefix) => {
        for (const entry of readdirSync(dir, { withFileTypes: true })) {
            const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
            if (entry.isDirectory()) {
                collect(join(dir, entry.name), relative);
            } else {
                files.push(relative);
            }
        }
    };
    collect(staging, '');
    // The team catalogs (step 16): pro-teams.json from roku/data, college-teams.json copied from MMTVL at build.
    // Step 25 (D61, D62): bslib's MIT notice, since bsc ships source/bslib.brs in every build.
    const missing = ['data/pro-teams.json', 'data/college-teams.json', 'licenses/bslib.txt'].filter((file) => !files.includes(file));
    if (missing.length > 0) {
        fail(`build:release: missing from the release build: ${missing.join(', ')}`);
    }
    // Probe code is the probes folder and assets, and everything that names their components or fields. The one
    // allowed mention is main's deletion of the probe registry section (security L-6), taken out before the check.
    const probeCode = /ProbesScreen|ProbeTask|ProbeKit|ProbeSynthetic|probeLaunch|mmtvl-probe|\[PROBE\]|pkg:\/probes/;
    const allowedProbeText = /CreateObject\("roRegistry"\)\.Delete\("mmtvl-probe"\)/g;
    // Step 22 (D54): the DEBUG memory console line (main.bs, MemoryRelief.consoleLine) is DEBUG-only too.
    const debugOnlyCode = /MemoryRelief_consoleLine|memoryTimer|"Using "|highest since launch/;
    const problems = files.filter((file) => /probe/i.test(file));
    for (const file of files.filter((name) => /\.(brs|xml)$|^manifest$/.test(name))) {
        const text = readFileSync(join(staging, file), 'utf8').replace(allowedProbeText, '');
        if (probeCode.test(text)) {
            problems.push(`${file} names probe code`);
        }
        // Code lines only: comments may name it.
        const code = text.split('\n').filter((line) => !/^\s*'/.test(line)).join('\n');
        if (debugOnlyCode.test(code)) {
            problems.push(`${file} has the DEBUG memory console line`);
        }
        if (/DEBUG\s*=\s*true/i.test(text)) {
            problems.push(`${file} has DEBUG=true`);
        }
    }
    if (problems.length > 0) {
        fail(`build:release: probe code in the release build:\n  ${problems.join('\n  ')}`);
    }
    const { rokuDeploy } = await import('roku-deploy');
    const zipPath = join(root, 'out', 'mmtvl-live-tv-release.zip');
    rmSync(zipPath, { force: true });
    await rokuDeploy.zipFolder(staging, zipPath);
    console.log(`Release build: ${files.length} files, no probe code, no DEBUG memory line; out/mmtvl-live-tv-release.zip`);
}

// M14 (L1): roku/manifest is the only version source.
function version() {
    let v;
    try {
        v = parseVersion(readFileSync(join(root, 'manifest'), 'utf8'));
    } catch (error) {
        fail(`version: ${error.message}`);
    }
    console.log(`MMTVL Live TV ${v.major}.${v.minor} build ${v.build}`);
}

function git(args) {
    const result = spawnSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    if (result.error) {
        fail(`Couldn't run git: ${result.error.message}`);
    }
    return { status: result.status ?? 1, stdout: (result.stdout ?? '').trimEnd() };
}

// M14: the manifest inside a zip (unzip -p, only that file): its version and whether bs_const is DEBUG=false.
// Throws with a one-line reason; label is how the zip is named in it. Used by nightly and deploy-nightly.
function zipManifest(zipPath, label) {
    const unzip = spawnSync('unzip', ['-p', zipPath, 'manifest'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    if (unzip.error || unzip.status !== 0) {
        throw new Error(`couldn't read the manifest from ${label}${unzip.error ? `: ${unzip.error.message}` : ''}.`);
    }
    let v;
    try {
        v = parseVersion(unzip.stdout);
    } catch (error) {
        throw new Error(`the zip's manifest: ${error.message}`);
    }
    return { v, debugOff: /^bs_const=DEBUG=false\r?$/m.test(unzip.stdout) };
}

// M14 (L2, L5–L9): a numbered nightly. Bumps roku/manifest's build_version (the number is spent from then on, even
// when a gate fails), runs every gate, checks the release zip's own manifest, copies it to
// out/nightly/<zipName> with its .sha256 and .source (the commit built from, and whether the tree was clean) and keeps
// the newest 3. A dry run goes to out/nightly-dry/ instead, which publish:nightly and deploy:nightly's default never read.
// The bump is left uncommitted.
function nightly() {
    // 1. Only a clean master (dry runs: ROKU_NIGHTLY_ALLOW_BRANCH=1, ROKU_NIGHTLY_ALLOW_DIRTY=1, as in scripts/release.sh).
    const head = git(['symbolic-ref', '--quiet', '--short', 'HEAD']);
    const branch = head.status === 0 && head.stdout ? head.stdout : '(detached HEAD)';
    if (branch !== 'master') {
        if (process.env.ROKU_NIGHTLY_ALLOW_BRANCH === '1') {
            console.log(`Dry run: HEAD is on ${branch}, not master (ROKU_NIGHTLY_ALLOW_BRANCH=1).`);
        } else {
            fail(`nightly: HEAD is on ${branch}, not master. Nightlies are made from master (dry runs: ROKU_NIGHTLY_ALLOW_BRANCH=1).`);
        }
    }
    const status = git(['status', '--porcelain']);
    if (status.status !== 0) {
        fail('nightly: git status failed.');
    }
    if (status.stdout) {
        if (process.env.ROKU_NIGHTLY_ALLOW_DIRTY === '1') {
            console.log(`Dry run: building with uncommitted changes (ROKU_NIGHTLY_ALLOW_DIRTY=1):\n${status.stdout}`);
        } else {
            console.error(status.stdout);
            fail('nightly: the working tree has uncommitted changes (listed above). Commit them first.');
        }
    }
    // Security 1: the commit built from (HEAD before the bump) goes in the zip's .source sidecar, with whether the tree
    // was clean. A dry run (another branch or a dirty tree) is kept apart in out/nightly-dry/, which nothing publishes.
    const built = git(['rev-parse', 'HEAD']);
    if (built.status !== 0 || !built.stdout) {
        fail('nightly: git rev-parse HEAD failed.');
    }
    const clean = !status.stdout;
    const dryRun = branch !== 'master' || !clean;
    if (!existsSync(join(root, 'node_modules'))) {
        fail('nightly: roku/node_modules is missing: run npm ci first.');
    }

    // 2. The bump. From here the number is spent (L2).
    const manifestPath = join(root, 'manifest');
    const manifestText = readFileSync(manifestPath, 'utf8');
    let v;
    try {
        const current = parseVersion(manifestText);
        v = { ...current, build: current.build + 1 };
        writeFileSync(manifestPath, withBuild(manifestText, v.build));
    } catch (error) {
        fail(`nightly: ${error.message}`);
    }
    const stays = `The build number stays ${v.build}; nothing was zipped.`;
    console.log(`Building MMTVL Live TV ${v.major}.${v.minor} build ${v.build}`);

    // 3. The gates, in order, stopping at the first failure; the last is the release build (L6).
    const gates = ['build', 'lint', 'test:local', 'test:tools', 'build:release'];
    for (const gate of gates) {
        console.log(`\n== Gate: npm run ${gate}`);
        if (run('npm', ['run', gate]) !== 0) {
            console.error(`nightly: npm run ${gate} failed.`);
            fail(stays);
        }
        console.log(`== Gate passed: npm run ${gate}`);
    }
    console.log(`\nAll ${gates.length} gates passed.`);

    // 4. The zip itself: its manifest has this build number and DEBUG off.
    const releaseZip = join(root, 'out', 'mmtvl-live-tv-release.zip');
    let zipped;
    let debugOff;
    try {
        ({ v: zipped, debugOff } = zipManifest(releaseZip, 'out/mmtvl-live-tv-release.zip'));
    } catch (error) {
        console.error(`nightly: ${error.message}`);
        fail(stays);
    }
    if (zipped.major !== v.major || zipped.minor !== v.minor || zipped.build !== v.build) {
        console.error(`nightly: the zip's manifest says ${zipped.major}.${zipped.minor} build ${zipped.build}, not ${v.major}.${v.minor} build ${v.build}.`);
        fail(stays);
    }
    if (!debugOff) {
        console.error('nightly: the zip\'s manifest doesn\'t have bs_const=DEBUG=false.');
        fail(stays);
    }
    console.log(`The zip's manifest: build_version=${zipped.build}, bs_const=DEBUG=false.`);

    // 5. The local copy (L8, L9) with its SHA-256 in shasum -a 256 format and its .source; only the newest 3 are kept
    // (in each folder: out/nightly/, or out/nightly-dry/ for a dry run).
    const folder = dryRun ? 'nightly-dry' : 'nightly';
    const nightlyDir = join(root, 'out', folder);
    mkdirSync(nightlyDir, { recursive: true });
    const name = zipName(v);
    const zipPath = join(nightlyDir, name);
    // Security N2: an earlier run's .sha256 and .source for this name go first, so they never sit beside another zip.
    for (const file of [`${zipPath}.sha256`, `${zipPath}.source`]) {
        rmSync(file, { force: true });
    }
    copyFileSync(releaseZip, zipPath);
    const sha256 = createHash('sha256').update(readFileSync(zipPath)).digest('hex');
    writeFileSync(`${zipPath}.sha256`, `${sha256}  ${name}\n`);
    writeFileSync(`${zipPath}.source`, sourceRecord({ commit: built.stdout, clean, sha256 }));
    for (const old of keepNewest(readdirSync(nightlyDir), 3)) {
        console.log(`Removing ${old}`);
        for (const file of [old, `${old}.sha256`, `${old}.source`]) {
            rmSync(join(nightlyDir, file), { force: true });
        }
    }

    // 6.
    console.log(`\nNightly${dryRun ? ' (dry run; never published)' : ''}: out/${folder}/${name}`);
    console.log(`SHA-256: ${sha256}`);
    console.log(`Built from ${built.stdout.slice(0, 9)}${clean ? '' : ' with uncommitted changes'}.`);
    if (dryRun) {
        console.log('Next: put roku/manifest back (git checkout roku/manifest); a dry run\'s number isn\'t a real nightly.');
    } else {
        console.log(`Next: commit roku/manifest as "Roku build ${v.build}" on master.`);
    }
}

// M14: sideloads a nightly, the given zip or the newest in out/nightly/ by build number, with roku-deploy's
// publish(): Replace (then Install), never Delete, so the registry stays if a replace keeps it (Q33).
// Only a zip whose own manifest says bs_const=DEBUG=false; checked before anything connects.
async function deployNightly() {
    const { host, password } = loadDevice();
    // Never print the password, even inside a library's error text.
    const redact = (text) => String(text ?? '').replaceAll(password, '<password>');

    let zipPath;
    let label;
    const given = process.argv[3];
    if (given) {
        // npm runs the script in roku/; a relative path is the caller's, from where npm was run.
        zipPath = resolve(process.env.INIT_CWD ?? process.cwd(), given);
        label = given;
        if (!existsSync(zipPath)) {
            fail(`deploy:nightly: ${label} doesn't exist.`);
        }
    } else {
        const nightlyDir = join(root, 'out', 'nightly');
        const name = existsSync(nightlyDir) ? newestZip(readdirSync(nightlyDir)) : null;
        if (!name) {
            fail('deploy:nightly: no nightly zip in out/nightly/: run npm run nightly first, or give a zip (npm run deploy:nightly -- <zip>; a dry run\'s are in out/nightly-dry/).');
        }
        zipPath = join(nightlyDir, name);
        label = `out/nightly/${name}`;
    }

    let v;
    let debugOff;
    try {
        ({ v, debugOff } = zipManifest(zipPath, label));
    } catch (error) {
        fail(`deploy:nightly: ${error.message} Nothing was installed.`);
    }
    if (!debugOff) {
        fail(`deploy:nightly: ${label}'s manifest doesn't have bs_const=DEBUG=false: only release builds (npm run nightly) are installed this way. Nothing was installed.`);
    }
    const versionText = `${v.major}.${v.minor}`;
    console.log(`Installing ${label} (MMTVL Live TV ${versionText} build ${v.build}) on ${host}.`);

    const { rokuDeploy } = await import('roku-deploy');
    let installed;
    try {
        installed = await rokuDeploy.publish({ host, password, outDir: dirname(zipPath), outFile: basename(zipPath) });
    } catch (error) {
        fail(`deploy:nightly: installing on ${host} failed: ${redact(error.message)}`);
    }
    // publish() also returns, as a success, the installer's "Identical to previous version -- not replacing".
    const answer = String(installed?.message ?? '');
    if (/Identical to previous version/i.test(answer)) {
        console.log(`MMTVL Live TV ${versionText} build ${v.build} was already installed on ${host}; the Roku kept it (it said "${redact(answer)}").`);
    } else if (answer && answer !== 'Successful deploy') {
        console.log(`Uploaded MMTVL Live TV ${versionText} build ${v.build} to ${host}; the Roku said "${redact(answer)}". Settings → About should say "Version ${versionText} Build ${v.build}".`);
    } else {
        console.log(`Installed MMTVL Live TV ${versionText} build ${v.build} on ${host}. Settings → About should say "Version ${versionText} Build ${v.build}".`);
    }

    // An optional read-back over ECP. Unverified: whether /query/apps reports the dev app's version, and in what
    // form (step 7 settles it). Anything missing or unexpected is printed as is and never fails the deploy.
    try {
        const response = await fetch(`http://${host}:8060/query/apps`, { signal: AbortSignal.timeout(5000) });
        const body = response.ok ? await response.text() : '';
        const app = /<app\b[^>]*\bid="dev"[^>]*>/.exec(body);
        const reported = app ? /\bversion="([^"]*)"/.exec(app[0]) : null;
        if (!response.ok) {
            console.log(`ECP read-back: /query/apps answered ${response.status}; About on the TV is the check.`);
        } else if (!app) {
            console.log('ECP read-back: no dev app in /query/apps; About on the TV is the check.');
        } else if (!reported) {
            console.log('ECP read-back: the dev app has no version attribute; About on the TV is the check.');
        } else {
            const expected = `${versionText}.${v.build}`;
            const same = reported[1] === expected ? 'matches' : `isn't ${expected} (the form is unverified)`;
            console.log(`ECP read-back: the dev app's version is "${reported[1]}", which ${same}.`);
        }
    } catch (error) {
        console.log(`ECP read-back: couldn't ask ${host} (${redact(error.message)}); About on the TV is the check.`);
    }
}

// M14 (L3, L4, L7): publish:nightly -- <N> [--stable]. Only after the user's yes. Refuses, with one line and before
// anything is tagged, unless: --stable only from 1.0; gitleaks runs; out/nightly/<zipName> for build N exists, matches
// its .sha256 and is a DEBUG=false build N; its .source says it was built from a clean tree at a commit HEAD differs
// from only in roku/manifest (security 1); HEAD's roku/manifest is build N, the tree is clean and HEAD is on master;
// HEAD is on origin/master after a fetch; the tag is neither local nor on origin; gitleaks finds nothing in the zip's
// contents or the notes; origin fetches and pushes to the same GitHub repo, not the private archive; the committer is a
// GitHub noreply address; gh runs and is signed in. Then it tags HEAD (annotated), pushes only that tag, creates the
// release (always --latest=false; a prerelease unless --stable) and reads it back. git, gh, unzip and gitleaks run
// through spawnSync with argument arrays, never a shell; nothing from roku/.env is read. The one temp dir
// (mmtvl-roku-*) is removed in finally, so nothing in here calls fail() (process.exit would skip the finally).
class Stop extends Error {}
const stop = (message) => {
    throw new Stop(message);
};

// M12's first commit on origin/master: the changes' base when there's no earlier roku-v* tag.
const firstRokuCommit = '414eb6b';
const rokuTagPattern = /^roku-v(\d+)\.(\d+)-build(\d+)$/;

function capture(command, args, cwd = root) {
    const result = spawnSync(command, args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    return {
        error: result.error,
        status: result.error ? 1 : (result.status ?? 1),
        stdout: (result.stdout ?? '').trimEnd(),
        stderr: (result.stderr ?? '').trimEnd()
    };
}

function publishNightly() {
    // afterPush: set once the tag is on origin; gives the "never re-tag, finish by hand" line for any later failure.
    const temp = { dir: null, afterPush: null };
    try {
        publishNightlySteps(temp);
    } catch (error) {
        if (!(error instanceof Stop)) {
            // Security L6: even an unexpected error after the push says that the tag is out there.
            if (temp.afterPush) {
                console.error(`publish:nightly: ${temp.afterPush()}`);
            }
            throw error;
        }
        console.error(`publish:nightly: ${error.message}`);
        process.exitCode = 1;
    } finally {
        if (temp.dir) {
            rmSync(temp.dir, { recursive: true, force: true });
        }
    }
}

function publishNightlySteps(temp) {
    const repoRoot = resolve(root, '..');
    const gitIn = (args) => {
        const result = capture('git', ['-C', repoRoot, ...args]);
        if (result.error) {
            stop(`couldn't run git: ${result.error.message}`);
        }
        return result;
    };

    // The arguments: a build number and, optionally, --stable.
    const args = process.argv.slice(3);
    const stable = args.includes('--stable');
    const rest = args.filter((arg) => arg !== '--stable');
    if (rest.length !== 1 || !/^\d+$/.test(rest[0])) {
        stop('usage: npm run publish:nightly -- <build number> [--stable]');
    }
    const n = Number.parseInt(rest[0], 10);

    // HEAD's manifest gives the version (and must be build N, checked below, after the zip).
    const shown = gitIn(['show', 'HEAD:roku/manifest']);
    if (shown.status !== 0) {
        stop('couldn\'t read roku/manifest at HEAD. Nothing was tagged.');
    }
    let head;
    try {
        head = parseVersion(shown.stdout);
    } catch (error) {
        stop(`HEAD's roku/manifest: ${error.message} Nothing was tagged.`);
    }
    const v = { major: head.major, minor: head.minor, build: n };
    const versionText = `${v.major}.${v.minor}`;

    // L3: stable only from 1.0.
    if (stable && v.major < 1) {
        stop(`--stable needs version 1.0 or later, and HEAD's manifest says ${versionText}: the Roku app is nightly-only until M12 is Done (L3). Nothing was tagged.`);
    }

    // gitleaks scans the zip and the notes below; without it nothing is published.
    if (capture('gitleaks', ['version']).status !== 0) {
        stop('gitleaks isn\'t installed (or doesn\'t run), and the zip is scanned with it before publishing: brew install gitleaks. Nothing was tagged.');
    }

    // The zip for build N (out/nightly/ only, never a dry run's out/nightly-dry/), its SHA-256 and its own manifest.
    const name = zipName(v);
    const label = `out/nightly/${name}`;
    const zipPath = join(root, 'out', 'nightly', name);
    if (!existsSync(zipPath)) {
        stop(`${label} doesn't exist: run npm run nightly for build ${n} first (it keeps only the newest 3). Nothing was tagged.`);
    }
    const shaPath = `${zipPath}.sha256`;
    if (!existsSync(shaPath)) {
        stop(`${label}.sha256 doesn't exist. Nothing was tagged.`);
    }
    const sha256 = createHash('sha256').update(readFileSync(zipPath)).digest('hex');
    const recorded = (readFileSync(shaPath, 'utf8').trim().split(/\s+/)[0] ?? '').toLowerCase();
    if (recorded !== sha256) {
        stop(`${label}'s SHA-256 doesn't match ${name}.sha256: the zip or its .sha256 changed after npm run nightly. Nothing was tagged.`);
    }
    let zipped;
    try {
        zipped = zipManifest(zipPath, label);
    } catch (error) {
        stop(`${error.message} Nothing was tagged.`);
    }
    if (zipped.v.major !== v.major || zipped.v.minor !== v.minor || zipped.v.build !== n || !zipped.debugOff) {
        stop(`${label}'s own manifest isn't a DEBUG=false ${versionText} build ${n}. Nothing was tagged.`);
    }

    // HEAD: its manifest is build N, the tree is clean, and it's master.
    if (head.build !== n) {
        stop(`HEAD's roku/manifest is build ${head.build}, not ${n}: publish from the commit that set build ${n} ("Roku build ${n}"). Nothing was tagged.`);
    }
    const status = gitIn(['status', '--porcelain']);
    if (status.status !== 0) {
        stop('git status failed. Nothing was tagged.');
    }
    if (status.stdout) {
        stop(`the working tree has uncommitted changes (${status.stdout.split('\n').length} in git status): commit or remove them first. Nothing was tagged.`);
    }
    const branchRef = gitIn(['symbolic-ref', '--quiet', '--short', 'HEAD']);
    const branch = branchRef.status === 0 && branchRef.stdout ? branchRef.stdout : '(detached HEAD)';
    if (branch !== 'master') {
        stop(`HEAD is on ${branch}, not master: nightlies are published from master. Nothing was tagged.`);
    }

    // Security 1: the zip was built from a clean tree, at a commit HEAD differs from only in roku/manifest.
    const sourcePath = `${zipPath}.source`;
    const sourceText = existsSync(sourcePath) ? readFileSync(sourcePath, 'utf8') : null;
    const sourceRefusal = buildSourceRefusal(sourceText,
        (commit) => gitIn(['diff', '--quiet', commit, 'HEAD', '--', '.', ':!roku/manifest']).status, sha256);
    if (sourceRefusal) {
        stop(`${label} ${sourceRefusal}. Nothing was tagged.`);
    }

    // L7: the bump commit is already on origin/master, so the tag never points at an unpushed commit.
    if (gitIn(['fetch', '--quiet', 'origin']).status !== 0) {
        stop('git fetch origin failed. Nothing was tagged.');
    }
    if (gitIn(['merge-base', '--is-ancestor', 'HEAD', 'origin/master']).status !== 0) {
        stop(`HEAD isn't on origin/master: push the "Roku build ${n}" commit to master first. Nothing was tagged.`);
    }

    // The tag is new, here and on origin.
    const tag = tagName(v);
    if (gitIn(['rev-parse', '-q', '--verify', `refs/tags/${tag}`]).status === 0) {
        stop(`the tag ${tag} already exists here: build numbers are never reused (L2). Nothing was tagged.`);
    }
    const remoteTagOutput = () => {
        const listed = gitIn(['ls-remote', '--tags', 'origin', `refs/tags/${tag}`]);
        return listed.status === 0 ? listed.stdout : null;
    };
    const remoteTag = remoteTagOutput();
    if (remoteTag === null) {
        stop('couldn\'t list origin\'s tags (git ls-remote). Nothing was tagged.');
    }
    if (remoteTag) {
        stop(`the tag ${tag} already exists on origin: build numbers are never reused (L2). Nothing was tagged.`);
    }

    // The notes, before anything is tagged, so gitleaks scans them with the zip (security L5). The changes are those
    // since the previous Roku tag by build number, else since M12's first commit; releaseNotes neutralises mentions.
    const title = releaseTitle(v, { stable });
    const previous = gitIn(['tag', '-l', 'roku-v*']).stdout.split('\n')
        .map((tagText) => ({ tagText, build: Number.parseInt(rokuTagPattern.exec(tagText)?.[3] ?? '-1', 10) }))
        .filter(({ build }) => build >= 0 && build < n)
        .sort((a, b) => b.build - a.build)[0]?.tagText ?? firstRokuCommit;
    const log = gitIn(['log', '--format=- %s', `${previous}..HEAD`, '--', 'roku', 'scripts/roku-export-settings.py']);
    if (log.status !== 0) {
        stop(`git log ${previous}..HEAD failed. Nothing was tagged.`);
    }
    const notes = releaseNotes({ v, sha256, zip: name, changes: log.stdout, stable });

    // gitleaks over the zip's contents and the notes, in a fresh temp dir, from the repo root with the repo's config.
    temp.dir = mkdtempSync(join(tmpdir(), 'mmtvl-roku-'));
    const contents = join(temp.dir, 'zip');
    if (capture('unzip', ['-q', zipPath, '-d', contents]).status !== 0) {
        stop(`couldn't unzip ${label} to scan it. Nothing was tagged.`);
    }
    const notesPath = join(temp.dir, 'notes.md');
    writeFileSync(notesPath, notes);
    // Security L1: gitleaks 8.30 silently skips every file whose name looks compressed or archived (".br", ".gz",
    // ".zip" and more anywhere in the name: main.brs scans 0 bytes), and the zip's code is all .brs. So every file is
    // scanned flat under a neutral name, f<n>.txt (PNGs as f<n>.png, which gitleaks skips: an image by its signature
    // bytes, not its name, security N5), with a map back for its report; and gitleaks must report exactly the text
    // files' bytes as scanned (N3). Only regular files and directories are taken: lstat, so a symlink in a doctored
    // zip is refused, never followed (N1).
    const scanDir = join(temp.dir, 'scan');
    mkdirSync(scanDir);
    const originals = new Map();
    let textBytes = 0;
    const flatten = (path, shown) => {
        const info = lstatSync(path);
        if (info.isDirectory()) {
            for (const entry of readdirSync(path).sort()) {
                flatten(join(path, entry), shown ? `${shown}/${entry}` : entry);
            }
            return;
        }
        if (!info.isFile()) {
            stop(`${label} holds ${shown}, which is neither a file nor a folder (a link?). Nothing was tagged.`);
        }
        const image = isPNG(readFileSync(path));
        const scanned = `f${originals.size + 1}${image ? '.png' : '.txt'}`;
        if (!image) {
            textBytes += info.size;
        }
        originals.set(scanned, shown);
        renameSync(path, join(scanDir, scanned));
    };
    flatten(contents, '');
    flatten(notesPath, '(the release notes)');
    const scan = capture('gitleaks', ['dir', '--config', 'scripts/gitleaks.toml', '--redact', '--no-banner', '--verbose', scanDir], repoRoot);
    const named = (text) => text.replace(/\S*\/scan\/(f\d+\.(?:txt|png))\b/g,
        (whole, scanned) => {
            const original = originals.get(scanned);
            return original === undefined ? whole : (original.startsWith('(') ? original : `${name}:${original}`);
        });
    if (scan.status !== 0) {
        // gitleaks redacts what it found; its report, with the zip's own paths, says where.
        for (const text of [scan.stdout, scan.stderr].filter(Boolean)) {
            console.error(named(text));
        }
        stop(`gitleaks found something in ${label}'s contents or the release notes, or failed (its report is above). Nothing was tagged.`);
    }
    const scannedBytes = /scanned ~(\d+) bytes/.exec(`${scan.stdout}\n${scan.stderr}`);
    if (!scannedBytes) {
        stop('gitleaks didn\'t say how many bytes it scanned, so a skipped file can\'t be ruled out. Nothing was tagged.');
    }
    if (Number(scannedBytes[1]) !== textBytes) {
        stop(`gitleaks scanned ${scannedBytes[1]} bytes, not the ${textBytes} in ${label}'s text files and the notes, so something was skipped or isn't what it seems. Nothing was tagged.`);
    }
    console.log(`gitleaks: nothing found in ${label}'s ${originals.size - 1} files or the release notes (${scannedBytes[1]} bytes scanned, ${textBytes} in text files).`);

    // Security L3: origin fetches and pushes to the same GitHub repo, which every gh call names, and it isn't the
    // private archive (CLAUDE.md: never push there).
    const fetchURL = gitIn(['remote', 'get-url', 'origin']);
    const pushURL = gitIn(['remote', 'get-url', '--push', 'origin']);
    const repo = fetchURL.status === 0 ? githubRepo(fetchURL.stdout) : null;
    const pushRepo = pushURL.status === 0 ? githubRepo(pushURL.stdout) : null;
    if (!repo || !pushRepo) {
        stop('origin isn\'t a GitHub repo (its fetch or push URL). Nothing was tagged.');
    }
    if (repo.toLowerCase() !== pushRepo.toLowerCase()) {
        stop(`origin fetches from ${repo} but pushes to ${pushRepo}. Nothing was tagged.`);
    }
    if (/\/mmtvl-private$/i.test(repo)) {
        stop(`origin is ${repo}, the private archive: never push there. Nothing was tagged.`);
    }
    // Security L4: the annotated tag goes public with the committer's name and email.
    const email = identEmail(gitIn(['var', 'GIT_COMMITTER_IDENT']).stdout);
    if (!email || !/@users\.noreply\.github\.com$/i.test(email)) {
        stop('the committer email (git var GIT_COMMITTER_IDENT) isn\'t a users.noreply.github.com address, and the tag would show it. Nothing was tagged.');
    }
    // gh is the last tool needed, and it must be signed in, or the tag would be pushed with no release (QA minor).
    if (capture('gh', ['--version']).status !== 0) {
        stop('gh isn\'t installed (or doesn\'t run). Nothing was tagged.');
    }
    if (capture('gh', ['auth', 'status', '--hostname', 'github.com']).status !== 0) {
        stop('gh isn\'t signed in to github.com (gh auth status). Nothing was tagged.');
    }

    // The release as gh arguments: always --latest=false, a prerelease unless --stable, and --verify-tag, so gh
    // never makes a tag itself.
    const createArgs = (notesFile) => ['release', 'create', tag, zipPath, '--repo', repo, '--verify-tag', '--title', title,
        '--notes-file', notesFile, '--latest=false', ...(stable ? [] : ['--prerelease'])];
    const byHand = (notesFile) => `gh ${createArgs(notesFile).map((arg) => (/[\s"']/.test(arg) ? JSON.stringify(arg) : arg)).join(' ')}`;
    // Once the tag is pushed: keep the notes where a by-hand run can use them, and say never to re-tag.
    const keepNotes = () => {
        const kept = join(root, 'out', 'nightly', `${tag}-notes.md`);
        writeFileSync(kept, notes);
        return kept;
    };
    const finishByHand = (what) => `${what}; the tag ${tag} is pushed (never re-tag it). Create the release by hand: ${byHand(keepNotes())}`;

    // 1. The annotated tag on HEAD; then only that tag is pushed (security L2: --no-follow-tags).
    if (gitIn(['tag', '-a', tag, '-m', title, 'HEAD']).status !== 0) {
        stop(`git tag ${tag} failed. Nothing was pushed.`);
    }
    const pushed = gitIn(['push', '--no-follow-tags', 'origin', `refs/tags/${tag}`]);
    if (pushed.status !== 0) {
        // Security L6: a push can fail after the remote took the tag; only a tag that isn't there is removed here.
        const reason = pushed.stderr.split('\n').pop() ?? '';
        const there = remoteTagOutput();
        if (there) {
            temp.afterPush = () => finishByHand('pushing the tag reported a failure, but origin has it');
            stop(`${temp.afterPush()} (git said: ${reason})`);
        }
        if (there === null) {
            stop(`pushing the tag ${tag} failed (${reason}), and origin's tags couldn't be listed: check with git ls-remote --tags origin ${tag} before removing the local tag. Nothing was published.`);
        }
        gitIn(['tag', '-d', tag]);
        stop(`pushing the tag ${tag} to origin failed (${reason}); origin doesn't have it, and the local tag was removed. Nothing was published.`);
    }
    temp.afterPush = () => finishByHand('the run stopped after the push');
    console.log(`Pushed the tag ${tag}.`);

    // 2. The release, with the scanned notes written again in the temp dir (the scan's copy was renamed).
    const releaseNotesPath = join(temp.dir, 'release-notes.md');
    writeFileSync(releaseNotesPath, notes);
    const created = capture('gh', createArgs(releaseNotesPath));
    if (created.status !== 0) {
        if (created.stderr) {
            console.error(created.stderr);
        }
        stop(finishByHand('creating the release failed'));
    }
    temp.afterPush = null;
    console.log(`Created the release ${tag}${created.stdout ? `: ${created.stdout.split('\n').pop()}` : '.'}`);

    // 3. Read back: the release itself, then that "Latest" is still MMTVL's v… release.
    const problems = [];
    const viewed = capture('gh', ['release', 'view', tag, '--repo', repo, '--json', 'isPrerelease,isDraft,assets,tagName']);
    let release = null;
    try {
        release = viewed.status === 0 ? JSON.parse(viewed.stdout) : null;
    } catch {
        release = null;
    }
    if (!release) {
        problems.push(`reading the release ${tag} back failed: check its page`);
    } else {
        const assets = (release.assets ?? []).map((asset) => asset.name);
        console.log(`Read back: ${release.tagName}, prerelease ${release.isPrerelease}, draft ${release.isDraft}, assets ${assets.join(', ') || '(none)'}.`);
        if (release.tagName !== tag) {
            problems.push(`the release's tag is ${release.tagName}, not ${tag}`);
        }
        if (release.isPrerelease !== !stable) {
            problems.push(stable ? 'the release is a prerelease: edit it on GitHub' : 'the release isn\'t a prerelease: mark it as one on GitHub');
        }
        if (release.isDraft) {
            problems.push('the release is a draft: publish it on GitHub');
        }
        if (assets.length !== 1 || assets[0] !== name) {
            problems.push(`the release's assets aren't just ${name}: fix them on GitHub`);
        }
    }
    const latest = capture('gh', ['api', `repos/${repo}/releases/latest`, '--jq', '.tag_name']);
    console.log(`Read back: Latest is ${latest.status === 0 && latest.stdout ? latest.stdout : '(unknown)'}.`);
    if (latest.status !== 0 || !latest.stdout.startsWith('v')) {
        problems.push('"Latest" isn\'t an MMTVL v… release: set Latest back to MMTVL\'s newest release on GitHub');
    }
    if (problems.length > 0) {
        stop(`the release was made, but ${problems.join('; ')}. Nothing was deleted.`);
    }
    console.log(`Published ${title}: https://github.com/${repo}/releases/tag/${tag}`);
}

const commands = {
    deploy, test, console: console8085, 'test-local': testLocal, 'build-release': buildRelease, version, nightly,
    'deploy-nightly': deployNightly, 'publish-nightly': publishNightly
};
const command = commands[process.argv[2]];
if (!command) {
    fail('Usage: node tools/roku.mjs deploy | test | console | test-local | build-release | version | nightly | deploy-nightly [<zip>] | publish-nightly <N> [--stable]');
}
await command();
