# MMTVL Live TV for Roku

MMTVL's Live TV, rebuilt as a standalone Roku app (milestone M12 of [MMTVL](../README.md)). You open it from the Roku home screen and get your IPTV playlist with up to 6 XMLTV guides, a grid guide with groups, a full-screen player with an info banner, favorites, hidden channels and groups, My Teams (pro and college), Search, Match Guide, and HDHomeRun antenna channels where the Roku can play them.

**Unofficial and personal.** This app is a personal project. It isn't affiliated with or endorsed by Roku or any IPTV or guide provider, and it comes with no channels: you bring your own playlist and guides. It's sideloaded in Roku's developer mode and is never published to the Roku Channel Store.

At runtime it depends on nothing else: no Mac, no MMTVL and no helper service. Anything a Roku can't do on its own is switched off, and **Settings → Device** says so.

> **Status: built off-device, not yet run on a Roku.** All the logic is tested on a Mac (`npm run test:local`), but no device session has happened yet. See [Not verified on a Roku yet](#not-verified-on-a-roku-yet).

## Developer mode and sideloading

1. **Turn on developer mode.** With the Roku remote, press Home ×3, Up ×2, Right, Left, Right, Left, Right. Turn on the installer and set a password; the Roku restarts. Give the Roku a DHCP reservation on your router, so its address doesn't change.
2. **Set up the tools** (Node.js 20.12 or newer), in `roku/`:
   ```sh
   npm ci
   cp .env.example .env     # then fill in ROKU_HOST (the Roku's address) and ROKU_DEV_PASSWORD
   ```
   `roku/.env` is gitignored. Never commit it.
3. **Sideload** a numbered build, in one of these ways:
   - **A downloaded nightly** (no tools needed): download `MMTVL-Live-TV-Roku-<version>-build<N>.zip` from the repo's Releases page (tags `roku-v…`, see [Versions and nightlies](#versions-and-nightlies)), open `http://<roku address>/` in a browser (user `rokudev`, the password from step 1) and upload the zip on the installer page.
   - **`npm run deploy:nightly`** installs the newest nightly you built (`npm run nightly`, `out/nightly/`), or the zip you give it (`npm run deploy:nightly -- <zip>`).
   - For development: `npm run deploy` builds the development build (DEBUG, with the Probes screen) and installs it.

A Roku holds **one sideloaded app at a time**: uploading a build replaces the one there. Whether a replaced build keeps its settings isn't known yet (Q33). If they're gone, run the migration again.

Other commands, in `roku/`:

| Command | What it does |
|---|---|
| `npm run build` | The development build (DEBUG, Probes screen) → `out/mmtvl-live-tv.zip` |
| `npm run build:release` | The release build (DEBUG off, no probe code; checks itself) → `out/mmtvl-live-tv-release.zip` |
| `npm run lint` | bslint over the app, test and local builds |
| `npm run test:local` | The logic tests, off the device (brs-node) |
| `npm test` | The Rooibos build, installed on the Roku; results read from port 8085 (needs `.env`). **It deletes the installed MMTVL Live TV first, which erases its settings** (Rooibos's roku-deploy deletes the dev app). Afterwards: `npm run deploy:nightly`, then the migration again |
| `npm run console` | The Roku's BrightScript console (`nc <ROKU_HOST> 8085`) |
| `npm run version` | Prints the version in `manifest`, e.g. `MMTVL Live TV 0.1 build 2` |
| `npm run test:tools` | The build tools' own tests (`node --test tools/`) |
| `npm run nightly` | On a clean `master`: the next build number, every gate above, then the release build zipped as `out/nightly/MMTVL-Live-TV-Roku-<version>-build<N>.zip` with its `.sha256` and `.source` (the newest 3 are kept). Off `master` or with uncommitted changes (only with `ROKU_NIGHTLY_ALLOW_BRANCH=1` / `ROKU_NIGHTLY_ALLOW_DIRTY=1`) it's a dry run into `out/nightly-dry/`, never published |
| `npm run deploy:nightly` | Installs the newest nightly (or `-- <zip>`) on the Roku with Replace, never Delete (needs `.env`) |
| `npm run publish:nightly -- <N>` | The maintainer's: tags and publishes build N as a GitHub prerelease (see below) |

## Versions and nightlies

The Roku app has its own version, separate from MMTVL's: `major_version`, `minor_version` and `build_version` in `manifest` are the only place it's kept, and **Settings → About** shows it ("Version 0.1 Build 2"). Every build handed out gets the next build number, which is never reset or reused. The version stays 0.x while the app is a work in progress, and becomes 1.0 once it has been checked on a Roku.

Builds are published on the repo's **Releases** page as **prereleases** tagged `roku-v<version>-build<N>` (e.g. `roku-v0.1-build2`) and titled "(nightly, WIP)". They are never the "Latest" release, which stays MMTVL for the Mac. Each one is the release build (DEBUG off, no probe code), built from a committed `master` and scanned with gitleaks before it's published. To install one, download its zip, check it against the SHA-256 in the release notes (`shasum -a 256 MMTVL-Live-TV-Roku-*.zip`), and upload it on the installer page (step 3 above). Uploading replaces the installed build; if your settings are gone afterwards, run the migration again.

Making one (the maintainer): `npm run nightly` on a clean `master` → commit `manifest` as `Roku build <N>` → push → `npm run publish:nightly -- <N>`, which refuses unless that commit is on `origin/master`, the zip was built from it, and gitleaks finds nothing in the zip or the notes.

## Moving your settings from MMTVL

On the Mac that runs MMTVL, on the same network as the Roku, with MMTVL Live TV sideloaded:

```sh
python3 -I scripts/roku-export-settings.py               # finds the Rokus; pick one
python3 -I scripts/roku-export-settings.py --roku <the Roku's IP address>
python3 -I scripts/roku-export-settings.py --dry-run     # only shows what would be sent: counts and hosts
```

- The script reads the playlist and guide addresses from MMTVL's Keychain items (macOS may ask to allow it) and the Live TV files in `~/Library/Application Support/MMTVL/`.
- It lists the Rokus it finds by name, the last 4 characters of the serial number, and the IP address. **Check the IP address against the Roku's Settings → Network → About** before you pick one: any device on the network can claim a Roku's name.
- It serves the settings once, over plain HTTP, on a one-time address that only the chosen Roku may fetch. The address expires after 10 minutes. Then it opens the app on the Roku.
- The TV shows what came over (**From** the Mac's address, the playlist's host, how many guides, favorites and so on). **Replace Settings** replaces the Roku's settings; Cancel changes nothing.
- If the Roku refuses (HTTP 403), allow it under Settings → System → Advanced system settings → Control by mobile apps.

**What moves:** the playlist and guide addresses; favorites, hidden channels and groups, and My Teams; guide matches; the last channel, group and recent channels; Channel Up's direction, Use the Playlist's Guide, the My Teams matching switches, Use Antenna and Guide from SiliconDust. **What doesn't:** the guide data (the Roku downloads it), Multiview, and the Roku's own settings (Channel Logos, the tuner address). Nothing is sent back to the Mac, and nothing syncs afterwards. Run the script again to replace the Roku's settings.

Without a Mac, type the playlist and guide addresses in Settings → Live TV.

## On low-end Rokus (Settings → Device)

At launch the app reads the Roku's memory limit, its UI resolution and what it can decode, and sorts it into a class. **Low** is a memory limit of 512 MB or less (or an unknown one), or a 720p UI; everything else is **High**. These thresholds are provisional until they're measured on real Rokus.

| Feature | High | Low | Why |
|---|---|---|---|
| Guide window | 36 hours | 24 hours | The guide's programmes are the largest thing the app holds in memory. At most 60,000 programmes are kept across all guides (25,000 on Low); a guide past that reads "guide shortened". |
| Compressed (`.gz`) guides | Any size | Up to 2 MB compressed | Roku has no gunzip, so the app inflates them itself, which is slow and needs room. Larger ones read "Can't read .gz on this Roku". |
| Channel Logos | On | On, with a one-time notice | Logos use texture memory. A Low Roku shows a notice the first time the app opens, pointing to Settings → Device, where logos can be turned off. |
| Antenna MPEG-2 channels | Where the Roku decodes MPEG-2 | The same | Most US over-the-air channels are MPEG-2, which many Rokus can't decode. Those channels are hidden, and the Device page says so. |
| Dolby Digital (AC-3) | Shown | Shown | Information only. |

**When memory runs short** (any Roku; Roku OS 15.2 warns at 80, 85, 90 and 95 % of the app's limit, older versions once at 80 %), the app lets go of things, and they stay off until the app is opened again:

- 80 %: channel logos, and Search's title index (the next search builds it again);
- 85 %: also, the guide window shrinks to 12 hours;
- 90 %: also, My Teams matches only game channels, not programmes on other channels or upcoming games.

Settings → Device then shows "Off: Low Memory" or "12 Hours: Low Memory". The saved Channel Logos choice is kept.

## Not verified on a Roku yet

Everything below was built and tested on a Mac only. The first device sessions (the plan's steps 1, 4, 15 and 23) check it:

- that provider HLS streams play and how quickly channels start;
- how fast `.gz` guides inflate and large guides are read, and whether `cachefs:` holds them on a Streaming Stick;
- HDHomeRun antenna channels: whether a Roku plays the tuner's raw MPEG-TS, MPEG-2 and 1080i, whether a broadcast finds tuners, and whether `hdhomerun.local` resolves. Each of these is a switch in `source/lib/AntennaConfig.bs`, set to a best guess;
- the memory alerts, the memory use over a 2-hour run on a stick, and the 720p layouts;
- whether settings survive replacing the build (Q33), and the migration end to end (ECP launch under "Limited");
- the guide grid's behaviour, the keyboard (including pasting from the Roku mobile app), and the look on a TV.

Multiview isn't in this app: a Roku plays one video at a time, and its multi-decode API isn't public (Q30).

## Security and privacy

- **Settings are stored in plain text.** The playlist and guide addresses, which usually carry your account's username, password or token, are kept in the app's Roku registry (section `mmtvl`). A sideloaded Roku app has no keychain, so this can't be avoided. To wipe them: **Settings → Live TV → Remove Live TV Source** (one guide: its page → Remove Guide), or delete the app on the installer page (`http://<roku address>/`, Delete), which clears its registry on Roku OS 10.5 and later (reported on Roku's developer forum; not yet checked here).
- **Developer mode opens the Roku to your network.** The BrightScript console and debugger on port **8085** has no password: anyone on the network can connect, break into a running app and read its memory and registry, including those addresses. The installer page (behind its password) is on the network too, as is Roku's control API (ECP, port 8060), which every Roku has. **Use the Roku on a trusted home network only.**
- The migration is plain HTTP on the LAN, once, for at most 10 minutes, to the chosen Roku's address only.
- The app's console lines show hosts only: never a full playlist, guide or stream address, a token, an HDHomeRun `DeviceAuth` or a tuner's address. Downloaded guides are kept in the Roku's memory-backed cache (`cachefs:`) under hashed names and are gone after a restart.

## Third-party code

- **Shipped in the app:** [`@rokucommunity/bslib`](https://github.com/rokucommunity/bslib) 0.1.1 (MIT, © 2021 RokuCommunity), BrighterScript's runtime, which the compiler adds to every build as `source/bslib.brs`. Its license notice ships in the package as `licenses/bslib.txt`.
- **In the test build only** (`npm test`, `out/mmtvl-live-tv-test.zip`): the [Rooibos](https://github.com/rokucommunity/rooibos) test framework (`rooibos-roku`, MIT).
- **Build tools, not shipped:** `brighterscript`, `@rokucommunity/bslint`, `roku-deploy`, `rooibos-roku` and `brs-node` (all MIT), as npm devDependencies.
- Everything else is this project's own code, including the inflate, the XMLTV reader and the HDHomeRun discovery. Text is drawn in Roku's system font, and the images are made by the scripts in `tools/`. The team catalogs (`data/`) come from MMTVL.

MMTVL Live TV is MIT-licensed, like MMTVL (see [LICENSE](../LICENSE)).
