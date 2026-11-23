# M14 — Roku versioning and nightly releases

| | |
|---|---|
| Status | Planned |
| Depends on | M12 (the Roku app and its release build) |
| Master plan decisions used | D54; new D57 |
| Planned | 2026-11-22 |

## Next session starts here

- Planned 2026-11-22; nothing built yet. Start with step 1. Run `/build-plan docs/plans/M14-roku-versioning.md`.
- Steps 1–4 and 6 need no Roku and no network. Step 5 (the first nightly) pushes to `master`, pushes a tag and publishes a GitHub prerelease on the **public** repo. The user approved step 5's push to `master` (2026-11-22); **ask before `publish:nightly`** (the tag and the prerelease). Step 7 needs a Roku and is the user's. It fits in M12 step 15's device session.

## Goal

The Roku app gets its own version and release line, separate from MMTVL's. Every build handed out has a new build number. Settings → About on the Roku shows it ("Version 0.1 Build 2"), so it's always clear which build is installed. One command builds a numbered **nightly**: every gate runs, then the release build (DEBUG off, no probes) is zipped as `MMTVL-Live-TV-Roku-<major>.<minor>-build<N>.zip` with its SHA-256. One command sideloads a nightly onto the Roku. Once the user says yes, one command publishes it on the public repo as a **GitHub prerelease marked nightly and WIP**. It never takes MMTVL's "Latest" badge. The user's words (2026-11-22): "Roku should have it's own versioning/release"; "zips can go to public repo as 'nightly' so they can be noted as WIP".

## Out of scope

- **A stable (non-prerelease) Roku release.** The Roku stays at 0.x and nightly-only until M12 is Done, meaning its device steps 1, 4, 15 and 23 pass. The 1.0 path is written down (L3) but not run here.
- **Signed `.pkg` packages** (genkey, Package/Rekey on the device). A sideload needs only the zip. A package matters only for a beta or store channel, which D54 rules out.
- **Scheduled or CI nightlies.** The repo has no CI (`.github/` doesn't exist). "Nightly" names the channel, not a schedule. Builds are made on demand (L5).
- **Pruning old GitHub nightlies.** Q34, answered by the user on 2026-11-22: no pruning; every nightly stays on GitHub.
- MMTVL's own versioning, `scripts/test-build.sh`, `scripts/release.sh`: unchanged.

## Research & findings

**Where the version lives today**
- `roku/manifest:2-4`: `major_version=0`, `minor_version=1`, `build_version=1`, set by hand when M12 started and never changed. Nothing bumps it.
- `roku/package.json:3`: `"version": "0.1.0"`, a second, unrelated number, mirrored in `roku/package-lock.json:3,9`. Nothing reads it (the package is `"private": true`, and npm needs no version for a private package that's never published).
- The app reads the manifest at runtime through `roAppInfo`:
  - `roku/components/MainScene.bs:97-99` builds `m.versionShort` ("0.1") and `m.buildNumber` ("1") for Settings → About (`MainScene.bs:1079-1080`).
  - `MainScene.bs:566-567` returns "Version 0.1 Build 1".
  - `roku/components/probes/ProbesScreen.bs:85-86` shows the same in DEBUG builds.
  - So bumping `build_version` in the manifest is enough for the app to show the new number; no app code changes.

**The manifest's rules** (Roku's docs, `rokudev/dev-doc` branch v2.0, `docs/DEVELOPER/getting-started/architecture/channel-manifest.md:73-75`; developer.roku.com refused fetches in M12)
- `major_version`, `minor_version` and `build_version` are integers: "major portion of the app version", "minor portion", "build number". The example is `build_version=00150`.
- No upper limit is documented. **Unverified:** whether the installer or Settings show `build_version` anywhere besides our own About screen. Check on the Roku in step 7.

**The build tools** (`roku/tools/roku.mjs`)
- `build-release` (`roku.mjs:150-210`):
  - compiles `bsconfig.release.json` into `out/release-staging/`;
  - sets the staged manifest's `bs_const` to `DEBUG=false` (`:156-161`);
  - checks for missing files (catalogs and the bslib notice, `:177-180`), probe code (`:183-204`) and `DEBUG=true`;
  - zips to the fixed name `out/mmtvl-live-tv-release.zip` (`:206-209`). Each build overwrites the last. The manifest is copied as is, so its version is whatever `roku/manifest` says.
- `deploy` (`roku.mjs:44-57`) builds the **DEBUG** build and calls `rokuDeploy.publish({ host, password, outDir: 'out', outFile: 'mmtvl-live-tv.zip' })`. Nothing sideloads the release zip.
- `loadDevice()` (`roku.mjs:19-34`) reads `ROKU_HOST` and `ROKU_DEV_PASSWORD` from `roku/.env` and never prints the password. Reuse it.

**roku-deploy 3.18.4** (`roku/node_modules/roku-deploy`, the app's own dependency)
- `publish()` uploads the zip with `mysubmit: 'Replace'` (`dist/RokuDeploy.js:436`) and doesn't delete the installed app first. Only `deploy()` does that: it calls `deleteInstalledChannel` when `deleteInstalledChannel` is true, which is the default (`RokuDeploy.js:893-895`, README "deleteInstalledChannel?: boolean = true").
- So `npm run deploy` and the new nightly deploy **replace** the app. Whether a replace keeps the registry (the user's settings) is M12's Q33, still pending.
- `incrementBuildNumber` (README) would set `build_version` to a `yymmddHHMM` timestamp at deploy. That doesn't fit: the number would differ per deploy, not per build, and wouldn't be in git. Not used (L2).
- `zipFolder(staging, zipPath)` is what `build-release` uses today.

**Rooibos (`npm test`) erases the Roku's settings.** This is a new finding.
- `rooibos-roku` 5.17.0's CLI sideloads through its own **roku-deploy 4.0.0-alpha.10** (`roku/node_modules/rooibos-roku/node_modules/roku-deploy`), with `rokuDeploy.sideload({ password, device, zip })` (`rooibos-roku/dist/cli.js:268-272`).
- `sideload` sets `deleteDevChannel = options.deleteDevChannel ?? true` (`…/roku-deploy/dist/RokuDeploy.js:127,151-153`) and deletes the installed dev app before installing. Deleting the dev app clears its registry (Q33's note).
- Rooibos passes no option to turn this off.
- So **`npm test` deletes the user's settings**: the playlist, guides and favorites. Afterwards the Roku runs the test app, not MMTVL Live TV. Step 3 warns before it runs; the README says so.

**GitHub releases**
- `gh` 2.103.3 has `gh release create --prerelease`, `--latest=false` ("explicitly NOT set as latest"), `--title`, `--notes-file`, `--target`.
- The repo's releases today are `v1.3.1` (Latest) and `v1.3.0`, MMTVL's. Tags are `v<version>`. A Roku tag needs its own prefix so the two lines never mix (L4).
- Repo style for build bumps: commits titled `Build 43` and `Version 1.3.1` directly on `master` (`git log`: `8204288`, `90695eb`).
- MMTVL's release body (`gh release view v1.3.1`) has these sections: Install, the SHA-256, What's in this release, Upgrading. The Roku notes follow the same shape.

**Node 20.12+** (M12's minimum) has `node:test` and `node --test` built in, so the version helpers can be tested with no new dependency.

## Design

**Local decisions**
- **L1: The manifest is the only version source.** `roku/manifest`'s `major_version`, `minor_version` and `build_version` are the Roku app's version. Remove `"version"` from `roku/package.json`, and its root entries in `package-lock.json` through `npm install --package-lock-only`. Nothing else stores the version. *Why:* there were two numbers that disagreed, and only the manifest reaches the device.
- **L2: The build number goes up by 1 for every nightly.** It is never reset (not when major or minor changes) and never reused, even when a later stage fails, like MMTVL's `CURRENT_PROJECT_VERSION`. The first nightly is **build 2**: build 1 was M12's development number. *Why:* one number identifies the installed build. A timestamp (roku-deploy's `incrementBuildNumber`) isn't in git and changes per deploy.
- **L3: The version is 0.x while the app is WIP.** It stays **0.1** until M12 is Done, meaning device steps 1, 4, 15 and 23 have passed. Then major and minor are set by hand to **1.0**, and that build may be released as stable: the same command with `--stable`, which drops "nightly"/WIP and `--prerelease` but still uses `--latest=false`. Not run in M14. *Why:* the user asked for WIP labelling; 1.0 means it has run on a Roku.
- **L4: Tags and titles.**
  - Tag: `roku-v<major>.<minor>-build<N>`, for example `roku-v0.1-build2`, annotated, on the commit that sets that build number.
  - Title: `MMTVL Live TV for Roku 0.1 build 2 (nightly, WIP)`.
  - Always `--prerelease --latest=false`, so "Latest" stays MMTVL's `v…` release.
  - Asset: the zip only. Its SHA-256 goes in the notes.
  - *Why:* a prefix that can't match MMTVL's `v*`; the build number makes each tag unique.
- **L5: Nightlies are made on demand.** They come from a clean `master`, by command, with no schedule or CI. *Why:* there's no CI, and every publish needs the user's yes.
- **L6: A nightly is the release build.** It is `build-release`'s output: DEBUG off and probe-checked. The DEBUG/probe build is never published. *Why:* the probes and info logs are for device sessions only.
- **L7: Building and publishing are separate commands.**
  - `npm run nightly` only bumps, gates, builds and zips. It leaves the bump uncommitted, like `scripts/test-build.sh`.
  - The orchestrator commits it as **`Roku build <N>`** on `master` (the repo's `Build 43` style).
  - Only after the user's yes, `npm run publish:nightly -- <N>` tags, pushes the tag and creates the prerelease. It refuses unless that commit is already on `origin/master`.
  - *Why:* each outward step gets its own yes (CLAUDE.md, outward-facing actions), and a tag never points at an unpushed commit.
- **L8: Local copies.** The newest **3** nightly zips (and `.sha256` files) are kept in `roku/out/nightly/`, which is gitignored with `roku/out/`. They aren't put on `~/Desktop`, where `deploy-mm.sh` prunes `MMTVL-*-build*.zip`. *Why:* the same rule as MMTVL's zips, without colliding with them.
- **L9: Zip name** `MMTVL-Live-TV-Roku-<major>.<minor>-build<N>.zip`. It starts `MMTVL-Live-TV-`, which `deploy-mm.sh`'s `MMTVL-*-build*.zip` glob would match if the file were ever put on the Desktop. That's one more reason for L8's folder.

**Files**
- `roku/tools/version.mjs` (new): pure helpers with no I/O beyond what's passed in:
  ```js
  export function parseVersion(manifestText)  // → { major, minor, build } (integers ≥ 0); throws with the bad key's name if a line is missing or not an integer
  export function withBuild(manifestText, n)   // → manifestText with only the build_version line changed to n; everything else byte-for-byte
  export function zipName({ major, minor, build })   // → "MMTVL-Live-TV-Roku-0.1-build2.zip"
  export function tagName({ major, minor, build })   // → "roku-v0.1-build2"
  export function releaseTitle(v, { stable })        // → "MMTVL Live TV for Roku 0.1 build 2 (nightly, WIP)" | "MMTVL Live TV for Roku 1.0 build 9"
  export function keepNewest(fileNames, n)           // → names to delete: all but the n highest build numbers among names matching zipName's pattern
  export function releaseNotes({ v, sha256, zip, changes, stable })   // → the Markdown body (template below)
  ```
- `roku/tools/version.test.mjs` (new): `node:test` tests for each helper (see Tests).
- `roku/tools/roku.mjs`: new commands `version`, `nightly`, `deploy-nightly`, `publish-nightly`. `build-release` is unchanged except that it's callable as a function, which it already is.
- `roku/package.json`: scripts `version` (`node tools/roku.mjs version`), `nightly`, `deploy:nightly`, `publish:nightly`, `test:tools` (`node --test tools/`). `"version"` is removed (L1).
- `roku/README.md`, `CLAUDE.md` (Roku (M12)), `docs/plans/MASTER_PLAN.md`: step 6.

**`npm run nightly`** (`roku.mjs nightly`)
1. Checks:
   - HEAD is on `master` and the working tree is clean. For dry runs: `ROKU_NIGHTLY_ALLOW_BRANCH=1`, `ROKU_NIGHTLY_ALLOW_DIRTY=1`, as in `scripts/release.sh:37-56`.
   - `roku/node_modules` exists.
2. Bump: `parseVersion` the manifest, write `withBuild(text, build + 1)` to `roku/manifest`, and print `Building MMTVL Live TV 0.1 build N`. From here the number is spent (L2).
3. Gates, in order, stopping at the first failure: `build` (probe assets + bsc), `lint`, `test:local`, `test:tools`, then `buildRelease()`. Each runs through `run(...)` with output shown. On failure: `The build number stays N; nothing was zipped.` and exit 1.
4. Check the zip itself: unzip only `manifest` from `out/mmtvl-live-tv-release.zip` (`unzip -p`) and confirm it has `build_version=N` and `bs_const=DEBUG=false`.
5. Copy it to `out/nightly/<zipName>`, write `<zipName>.sha256` (`shasum -a 256` format), and delete what `keepNewest(…, 3)` returns, with each zip's `.sha256`. Print each `Removing <name>`.
6. Print the zip's path and SHA-256, then `Next: commit roku/manifest as "Roku build N" on master.`

**`npm run deploy:nightly [-- <zip>]`** (`roku.mjs deploy-nightly`)
- `loadDevice()`; the zip is the given path or the newest in `out/nightly/`, by build number.
- Check the zip's manifest is `DEBUG=false` (as in nightly step 4).
- `rokuDeploy.publish({ host, password, outDir: dirname(zip), outFile: basename(zip) })`. That's Replace, never Delete, so the registry stays if Q33 allows.
- Print `Installed MMTVL Live TV 0.1 build N on <host>. Settings → About should say "Version 0.1 Build N".`
- Optional read-back: `GET http://<host>:8060/query/apps`, and if the `dev` app's `version` attribute is there, compare it. **Unverified:** whether ECP reports the dev app's version and in what form (`0.1.N`?). If it's missing or in another form, print it as is and don't fail. Step 7 settles it.

**`npm run publish:nightly -- <N> [--stable]`** (`roku.mjs publish-nightly`; only after the user's yes)
Refuses with one line each unless all of these hold:
- `out/nightly/<zipName>` for build N exists, and its SHA-256 matches its `.sha256`.
- `git show HEAD:roku/manifest` parses to build N, the tree is clean, and HEAD is on `master`.
- After `git fetch origin`, `git merge-base --is-ancestor HEAD origin/master` holds (the bump commit is pushed).
- Tag `tagName` doesn't exist locally (`git rev-parse -q --verify refs/tags/<tag>`) or on GitHub (`git ls-remote --tags origin <tag>`).
- gitleaks finds nothing in the zip's contents: unzip it to a fresh temp dir, then run `gitleaks dir --config scripts/gitleaks.toml --redact --no-banner <dir>` from the repo root. If gitleaks isn't installed, refuse.
- `--stable` only with `major ≥ 1` (L3).

Then:
1. `git tag -a <tag> -m "<title>" HEAD`, then `git push origin <tag>`.
2. `changes` = `git log --format='- %s' <previous roku-v* tag>..HEAD -- roku scripts/roku-export-settings.py`. Use the latest tag by build number, or `origin/master`'s first M12 commit `414eb6b` if there is none.
3. Write the notes with `releaseNotes` to a temp file, then `gh release create <tag> <zip> --title <title> --notes-file <file> --latest=false` plus `--prerelease` unless `--stable`.
4. Read back:
   - `gh release view <tag> --json isPrerelease,isDraft,assets,tagName` should show prerelease (for a nightly), not a draft, and one asset named `zipName`;
   - `gh api repos/{owner}/{repo}/releases/latest --jq .tag_name` should still start with `v`.
   Print both. Exit 1 if either is wrong. Nothing is deleted automatically; the line says what to fix.

**Release notes template** (`releaseNotes`; no hosts, addresses or provider names, since every value comes from the repo):
```markdown
# MMTVL Live TV for Roku 0.1 build 2 (nightly)

> **Nightly, work in progress.** Built off-device; not yet verified on a Roku (see roku/README.md, "Not verified on a Roku yet"). Not MMTVL for the Mac: that's the "Latest" release.

## Install (sideload)
1. Put the Roku in developer mode (roku/README.md, "Developer mode and sideloading").
2. Download `MMTVL-Live-TV-Roku-0.1-build2.zip` below; don't unzip it.
3. Open `http://<your Roku's address>/`, sign in as `rokudev`, and upload the zip on the installer page (Replace).
4. Settings → About should say "Version 0.1 Build 2".

SHA-256 of the zip:
`<sha256>`

## Changes since the last Roku build
<changes, or "- First Roku nightly.">

## Upgrading
Uploading replaces the installed build. If your settings are gone afterwards, run the migration again (`python3 -I scripts/roku-export-settings.py`, roku/README.md).
```
With `--stable`, the title loses "(nightly)", the WIP box is dropped, and Install says "Release". The README section and its wording are aligned in step 6.

## Implementation steps

- [ ] **1. Version helpers and one version source** `[implementer]`, files: `roku/tools/version.mjs` (new), `roku/tools/version.test.mjs` (new), `roku/package.json`, `roku/package-lock.json`, `roku/tools/roku.mjs`
  - Write the helpers in Design → Files, and the tests in Tests.
  - Add `test:tools` (`node --test tools/`) and `version` (prints `MMTVL Live TV 0.1 build 1` from `parseVersion` of `roku/manifest`).
  - Remove `"version"` from `package.json`, then `npm install --package-lock-only` (offline is fine: `--prefer-offline`). Only the root `version` entries in the lock may change. If anything else changes, stop and record it.
  - Don't change `roku/manifest` yet.
  - Done when:
    - `cd roku && npm run test:tools` shows all `version.test.mjs` tests passing (quote the `# pass` / `# fail 0` lines);
    - `npm run version` prints `MMTVL Live TV 0.1 build 1`;
    - `git diff roku/package-lock.json` shows only the removed root `version` lines;
    - the M12 gates pass: `npm run build && npm run lint && npm run test:local && npm run build:release` → "LOCAL TESTS: 742 passed, 0 failed", "Release build: 127 files, …".

- [ ] **2. `npm run nightly`** `[implementer]`, files: `roku/tools/roku.mjs`, `roku/package.json`
  - Build it as in Design → `npm run nightly`.
  - The QA run is a dry run on the step branch: `ROKU_NIGHTLY_ALLOW_BRANCH=1 ROKU_NIGHTLY_ALLOW_DIRTY=1 npm run nightly`. It bumps `roku/manifest` to build 2, and the orchestrator then **reverts the manifest** (`git checkout roku/manifest`): the real build 2 is step 5's.
  - Done when the dry run:
    - prints every gate passing, `out/nightly/MMTVL-Live-TV-Roku-0.1-build2.zip` and a SHA-256 that `shasum -a 256 -c` (run in `out/nightly/`) confirms;
    - its zip's manifest has `build_version=2` and `bs_const=DEBUG=false` (`unzip -p … manifest`).

    Also:
    - with three older fake zips (`…-build0.zip` etc., made by hand), only the newest 3 remain afterwards;
    - without the env vars on a branch, it refuses before bumping (manifest unchanged);
    - a forced lint failure (a temporary bad line, removed afterwards) stops it with "The build number stays 2; nothing was zipped."

- [ ] **3. `npm run deploy:nightly` and the `npm test` warning** `[implementer]`, files: `roku/tools/roku.mjs`, `roku/package.json`
  - `deploy-nightly` as in Design.
  - In `test()` (`roku.mjs:59-63`), print before Rooibos runs: `npm test installs the test app and deletes the installed MMTVL Live TV first, which erases its settings (Rooibos's roku-deploy deletes the dev app). Afterwards: npm run deploy:nightly, then run the migration again.` No prompt, since npm scripts run non-interactively.
  - No Roku is needed for QA. With no `roku/.env`, `deploy:nightly` stops with `loadDevice`'s line. Use a temporary `.env` whose `ROKU_HOST` is a TEST-NET address (`192.0.2.1`, RFC 5737) and any password: it fails to connect and the message names only the host. Check the zip choice and the DEBUG check with a hand-made zip whose manifest says `DEBUG=true`: it refuses before connecting.
  - Done when:
    - those three runs behave as described;
    - the password never appears in output (`grep` the captured output for it);
    - `npm test` without `.env` still stops with `loadDevice`'s line, and the warning prints before that line.

- [ ] **4. `npm run publish:nightly`** `[implementer]` `[security]`, files: `roku/tools/roku.mjs`, `roku/package.json`
  - Build it as in Design → `npm run publish:nightly`. Use `gh` and `git` through `spawnSync` with argument arrays (no shell strings). Temp dirs come from `mkdtempSync(join(tmpdir(), 'mmtvl-roku-'))`, removed in `finally`.
  - **QA must not create a tag or a release.** Exercise every refusal instead:
    - no zip for N;
    - a SHA-256 mismatch (an edited `.sha256`);
    - HEAD's manifest at another build (any commit before step 5);
    - a dirty tree;
    - a commit not on `origin/master` (the step branch);
    - an existing tag (make a lightweight local tag `roku-v0.1-build2` in a scratch clone, never pushed);
    - `--stable` at 0.1;
    - gitleaks missing (`PATH` without it).
  - Each refusal is one line and leaves no tag, no remote change and no temp dir.
  - Also check `releaseNotes`' output for build 2 by printing it with `node -e` from `version.mjs`.
  - Done when every refusal above is shown with its line, and `git tag -l 'roku-v*'` and `git ls-remote --tags origin 'roku-v*'` are empty afterwards.
  - Security review: the script runs `git push` and `gh release create` on a public repo. Check:
    - nothing from `.env` reaches git, gh or the notes;
    - the zip's contents are gitleaks-scanned;
    - the notes hold no host or address;
    - `--latest=false` is always passed.

- [ ] **5. The first nightly, build 2** `[release]`; the push to `master` is approved, and publishing needs the user's yes
  1. On a clean `master` (in this worktree: `git switch master && git pull`), run `cd roku && npm run nightly` → build 2. Quote the zip line and the SHA-256.
  2. Commit `roku/manifest` by path as `Roku build 2`.
  3. Run gitleaks over the commit:
     ```sh
     gitleaks git --config scripts/gitleaks.toml --log-opts="origin/master..master" --redact --no-banner .
     ```
  4. `git push origin master` (approved by the user for this step, 2026-11-22).
  5. **Ask, then** `npm run publish:nightly -- 2`.
  6. Read back: `gh release view roku-v0.1-build2` (prerelease, one asset), and `gh release list -L 3`, where `v1.3.1` is still Latest. Open the release page and check its text shows no address.
  - Done when both read-backs are quoted and the user has seen the release link.

- [ ] **6. Docs** `[doc]`, files: `roku/README.md`, `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this plan
  - `roku/README.md`:
    - a **Versions and nightlies** section: the version is in `manifest`, shown in Settings → About; nightlies on the repo's Releases page tagged `roku-v…`, prereleases marked WIP; install by uploading the zip; check the SHA-256;
    - the commands table gains `nightly`, `deploy:nightly`, `publish:nightly`, `test:tools`, `version`;
    - the `npm test` row says it deletes the installed app and its settings;
    - the "Sideload" step 3 points at `deploy:nightly` or a downloaded nightly first.
  - `CLAUDE.md` → Roku (M12):
    - the commands;
    - the versioning rules (L1–L4, L7);
    - the release checklist: nightly → commit `Roku build N` → gitleaks → push (ask) → `publish:nightly` (ask) → read back;
    - the `npm test` warning.
  - Master plan:
    - D57 (already added at planning; update to as-built if anything changed);
    - §6 M14 → Done;
    - Q33's note: `npm test` deletes; `deploy:nightly` replaces.
  - Then `git mv` this plan to `docs/plans/archive/` and fix its link.
  - Done when `grep -n 'deploy:nightly' roku/README.md CLAUDE.md` finds both, and the master plan row links the archive.

- [ ] **7. On the Roku** `[human]`, folded into M12 step 15's device session (no extra session)
  - `npm run deploy:nightly`. Settings → About says **"Version 0.1 Build 2"**. Note what the deploy's ECP read-back printed for the dev app's version (record the form under Deviations, and drop the read-back if ECP has no version).
  - Look at the installer page (`http://<roku>/`) and Roku Settings → System → About / the app's info (`*` on the app tile) for any version display, and record it.
  - **Q33:** with settings migrated, `npm run nightly` a build 3 (a real one, committed like step 5, unpublished if the user prefers) and `deploy:nightly` it. Are the playlist, guides and favorites still there? Record the answer in M12's Q33 and the master plan.
  - Done when the three observations are recorded here and in M12 step 15.

## Tests

`roku/tools/version.test.mjs` (`node:test`, run by `npm run test:tools`):
- `parseVersion` reads the real `roku/manifest` as `{0, 1, 1}`. It throws naming the key for a missing `build_version`, `build_version=abc`, `build_version=-1` and a missing `minor_version`. It accepts `build_version=00150` as 150.
- `withBuild` changes only the `build_version` line. The rest is byte-identical, including the `bs_const` line, comments, CRLF if present, and the trailing newline. A manifest without the line throws.
- `zipName` / `tagName` / `releaseTitle` give the exact strings in Design for `{0,1,2}` and, with `stable`, for `{1,0,9}`.
- `keepNewest`: given names for builds 2, 10, 3, 4, a `.sha256`, and an unrelated `mmtvl-live-tv.zip`, with n = 3, it returns only build 2's zip. It orders by number, not text (10 > 4). Unrelated names are never returned.
- `releaseNotes`: nightly notes have the WIP box, the zip name, the SHA-256 and "First Roku nightly." for no changes. Stable notes have no "nightly" and no WIP box. Neither contains `http://` with anything but `<your Roku's address>`.

Commands: `cd roku && npm run test:tools`, plus M12's gates (`npm run build && npm run lint && npm run test:local && npm run build:release`). MMTVL's Xcode suite is unaffected (no Swift changes); run it only if a step touches `MMTVL/`.

## Manual verification

- On this Mac: step 2's dry run, step 3's three runs, step 4's refusals.
- On GitHub (step 5, after the user's yes): the prerelease page, its zip download, and `shasum -a 256` of the download matching the notes. "Latest" is still MMTVL's.
- On the Roku (step 7, the user, in M12 step 15's session): About shows the build, the version display elsewhere, and Q33.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| A replace loses the registry (Q33) | Step 7: settings gone after `deploy:nightly` | Re-run the migration after each install (README already says so); consider an export/import of settings on the Roku in a later milestone |
| ECP doesn't report the dev app's version | Step 7: no `version` attribute | Drop the read-back; About on the TV is the check |
| A nightly zip leaks something private | gitleaks in `publish:nightly`, the user's look at the page | The zip holds only committed files; if anything is found, the release isn't made. If one is published by mistake: delete the release and tag (`gh release delete <tag> --cleanup-tag`) with the user's yes |
| A failed run leaves the manifest bumped but no zip | "The build number stays N" | Commit the bump anyway (L2: a spent number is never reused) or fix and re-run; the next nightly takes N+1 |
| The tag is pushed but `gh release create` fails | publish exits 1 after the push | Re-run only `gh release create` by hand with the printed arguments; never re-tag |
| `npm install --package-lock-only` rewrites more of the lock | Step 1's diff check | Edit only the root `version` lines by hand instead |

## Deviations & questions

*(Executors append here.)*
