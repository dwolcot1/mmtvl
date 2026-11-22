# M12 — Roku Live TV

| | |
|---|---|
| Status | In progress |
| Depends on | M4, M6b, M7j, M7l, M7m, M7n (the Live TV behaviour it clones) |
| Master plan decisions used | D9, D23, D26, D48, D49, D52; new D54, D55, D56 |
| Planned | 2026-11-18 |

## Next session starts here

- **Phase 0 (PR #1)** and **phase 1 (PR #2, stacked on PR #1)** are done off-device. Steps 1, 4 and every device check wait for the remote tester's Roku. The probe build is `cd roku && npm run build` → `roku/out/mmtvl-live-tv.zip`. **Ask the user before sending it.**
- **Automated run (user, 2026-11-22):** steps 18–22, 24 and 25 run without the user.
  - Every decision taken without the user is in **[M12-decisions-log.md](M12-decisions-log.md)**, with the reason and pros and cons.
  - Git: after QA, each step is committed, scanned with gitleaks and pushed. Each phase gets a PR when it's done, stacked on the one before. Once phase 6's automated steps are done, every gate runs again and the PRs are squash-merged in order (#1, #2, #4, #5, then phases 4–6), each rebased onto `master` first.
  - Device steps (1, 4, 15, 23) stay open for the user.
- **Branches stack:** `m12-phase0` (PR #1) → `m12-phase1` (#2) → `m12-step13` (#4, phase 2) → `m12-step14` (#5, phase 3) → `m12-step16` → `m12-step17` → `m12-step18` → `m12-step19` → `m12-step20` (#6, phase 4: base `m12-step14`) → **`m12-step21`** (phase 5's PR: head `m12-step21`, base `m12-step20`). Worktree `.claude/worktrees/step9`. Done and QA-passed: steps 2, 3, 5–14 and 16–21. `test:local`: 713 passed; script tests 40; MMTVL full suite 2096.
- **Next: step 22** (phase 6), then step 24 (security review) and step 25 (docs). Step 21 (Antenna) is built with every path gated (U1, D21–D44); its device checks are in its Deviations entry. Step 22 is the low-end pass: memory alerts drop logos and the search index; SearchView's render-thread imports (D19). Pencil: read frames with `execute` on the file's `uri`, read-only, and never save from this session.
- Gates for every Roku step: `cd roku && npm run build && npm run lint && npm run test:local` (264 passed at the end of phase 1), plus `npm run build:release`. No simulator runs with network access. Use a separate git worktree for parallel steps (`git worktree add -b m12-stepN .claude/worktrees/stepN <commit>`); the built-in isolation started from the wrong commit.

## Goal

MMTVL's Live TV, rebuilt as a **standalone Roku app** that is sideloaded in developer mode. On the TV, the user opens it from the Roku home screen and gets:

- the provider's playlist, with the guide from up to 6 XMLTV guides (the same matching and Match Guide overrides);
- a grid guide with groups (Search, Favorites, My Teams, Antenna, All Channels, the playlist's groups);
- a full-screen player with an info banner;
- favorites, hidden channels and groups;
- My Teams (pro and college);
- Search;
- HDHomeRun antenna channels, where the Roku can play them.

At runtime it depends on **nothing else**: no MMTVL, no Mac, no helper service (user, 2026-11-18). The user's MMTVL Live TV settings are **migrated once** by a script on the Mac (`scripts/roku-export-settings.py`). The app is tuned to run on low-end Rokus (Streaming Stick, Express). Features a device can't handle are switched off, and Settings → Device says why (D56).

**User choices (2026-11-18):**

- **Device:** none bought yet. A Roku Ultra is the reference, but the app is tuned for the Stick and Express, and features may depend on the device class, with a note where one is missing.
- **Repo:** `roku/` in this repo.
- **Scope:** all of Live TV.
- **Multiview:** probe first, then decide.
- **Rewind:** pause only.
- **No guide service:** "if it can't do it on device then we can't". Anything the Roku can't do on its own is left out, and the app says so.

## Out of scope

- **Multiview.** Roku plays one `Video` node at a time; on-device Multiview needs the undocumented `roMultiDecode` (Q30). Step 3 probes it, and step 4's decision creates **M13 Roku Multiview** or drops it. Mac- or service-side compositing is off the table (no runtime dependency).
- **Rewind beyond the live window.** Roku stays at least 30 s from the live edge, and the provider's window is 40 s. Only Roku's own pause buffer and short skips inside the window are offered. There is no equivalent of MMTVL's mpv back-cache (D7).
- **Store publishing**, a channel store listing, certification. Sideloading only.
- **Settings sync back to MMTVL**, or ongoing sync. Migration is one-way and can be run again to replace the Roku's settings.
- MMTVL's home screen, top shelf, phone remote, casting, receiver/TV control and Plex. Only Live TV is cloned.
- **Changing MMTVL app code.** Migration is a script; the only MMTVL change is a parity test (step 5, step 16).
- The relay and `StreamResolver` (D39). They're mpv/ffmpeg workarounds; Roku's player fetches HLS itself.

## Research & findings

### MMTVL parity: what the port must match (read 2026-11-18)

- **Channel ids decide whether migrated favorites, hidden channels, overrides and recents still work.** `ChannelList.make` (`MMTVL/IPTV/Sources/Channel.swift:60-84`):
  - Keeps http(s) entries that aren't VOD: no `/movie/` or `/series/` in the path, no `.mp4`/`.mkv`/`.avi`/`.mov` (:125-130).
  - The id is `"id:" + lowercase(tvg-id)`, else `"name:" + lowercase(entry name)`. Duplicates get `#2`, `#3`, … in playlist order.
  - The name is the entry name, else `tvg-name`, else `"Channel N"`. `feedName` (:87-97) turns `-H`/`-A` into "(Home Feed)"/"(Away Feed)".
  - The group is `group-title`, else the running `#EXTGRP`, else "Other".
  - Antenna ids are `antenna:<GuideNumber>` (`IPTV/Antenna/AntennaLineup.swift:9`).
- **M3U rules** (`IPTV/Sources/M3UParser.swift`):
  - Strips a BOM (:36) and splits on `\n` by scalars, so CRLF works (:47).
  - The header's `url-tvg`/`x-tvg-url` are split on commas, http(s) only, de-duplicated (:51-63).
  - Attributes match `([A-Za-z0-9_-]+)="([^"]*)"`, keys are lowercased and the first one wins (:92-101). The name is the text after the first comma outside quotes (:104-115).
  - `#EXTGRP` sets a running group (:67-69). The URL is the next non-`#` line (:72-80).
  - With neither a header nor an entry, it throws `notAPlaylist` (:84).
- **Guide matching** (`IPTV/EPG/EPGMatcher.swift:21-96`, D26): rule by rule, then guide by guide in priority order.
  1. The override, keyed by `overrideKey` (the antenna id, else the name), then the name, then the tvg-id, ignoring case. `""` means no guide, and an override only counts if its target id exists in some guide.
  2. tvg-id equals an EPG channel id, ignoring case.
  3. The normalized tvg-name or name equals a normalized display-name. Normalizing (:21-31) folds case and diacritics, turns `&` into "and" and `+` into "plus", splits on non-alphanumerics, drops `hd fhd uhd sd 4k hevc`, and joins.

  Nothing is fuzzy. `EPGSuggester` (IDF ranking, 70 lines) only feeds Match Guide.
- **XMLTV parsing** (`IPTV/EPG/XMLTVParser.swift`):
  - Channel ids and display-names are lowercased, with at most 16 names per channel, and repeated ids merged (:114-126).
  - Matching runs once, at the first `<programme>`, and decides which channel ids to keep (:130-131).
  - Fields: start, stop, title, sub-title, desc, category, episode-num (`onscreen`, else `xmltv_ns` → "S2 E1"; :150-188). A missing stop comes from the next programme (:190-201).
  - Times: `XMLTVDate.parse`. With no offset, a time is UTC.
- **Guide sizes:** US2 is 6.5 MB gz, 77 MB XML, 769 channels, 80,531 programmes, served as `application/octet-stream` (`archive/M4-live-tv.md:66,210`). FANDUEL1 is 110 KB gz (`archive/M6b-guide-management.md:39`). The playlist is about 30 KB and 118 entries (MASTER_PLAN §3).
- **Guide sources:** pasted guides if there are any; the playlist's `url-tvg` if there are none, or when `usePlaylistGuide` is on (`IPTV/IPTVLibrary.swift:1003-1008`). A guide is stale after 12 h and the playlist after 10 min (:17-18). `sourceID` = SHA-256 of the URL (:1070-1072).
- **Lineup:**
  - Group order: Favorites, My Teams, Antenna, All Channels, then the playlist's groups (`IPTV/Sources/ChannelPreferences.swift:85-104`, `Channel.swift:107-113`).
  - Live team games lead Favorites (`ChannelPreferences.swift:96-97`).
  - My Teams: Choose Teams…, then live channels (game entries first, then networks whose programme names a picked team), then up to 30 upcoming games within 72 h (`IPTV/Guide/GuideModel.swift:234`, `IPTV/Teams/TeamMatcher.swift:514-578`).
- **Teams:** `TeamMatcher.swift` is 764 lines, the biggest single port.
  - College: `IPTV/Teams/college-teams.json`, 381,837 bytes, 1,307 entries with keys `abbreviations, aliases, conference, id, league, name, nickname, school`.
  - Pro: 124 NFL/NBA/NHL/MLB teams hard-coded as `Team("lal", .nba, "Los Angeles Lakers", "Lakers")` (`TeamCatalog.swift:182-317`); ids are `league.abbr`.
  - Options: `TeamMatchOptions` (`TeamMatcher.swift:8`).
- **Keys** (D49, `IPTV/LiveTVModel.swift`):
  - Only Home leaves (:401-402); Back does nothing with nothing playing (:446-462).
  - **Player** (:534-584): Up/Down zap, Select toggles the banner (or retries an error), Back hides the overlays, else opens the guide, Menu opens the channel menu, and Channel Up/Down zap in the direction `channelUpMovesUpList` sets.
  - **Guide** (`GuideModel.swift:244-327`): Select plays, Menu opens the channel menu, Channel Up/Down page by 6 rows, Left from the first cell goes to the channel cell and then to the groups, and the group list loops with Search above it. Back returns to the playing channel (`LiveTVModel.swift:637-664`).
  - **Channel menu** (:912-941): Watch, (Multiview), Add/Remove Favorites, Move Up/Down (Favorites only), Add/Remove a team, Match Guide, Hide Channel. `LiveMenu` shows 8 rows (`IPTV/LiveMenu.swift:63-87`).
  - **Search** (`IPTV/Search/LiveSearchModel.swift:39-43,139-167`): from 2 characters; 8 channels, 12 teams, 40 programmes in the next 24 h. Team ranks: exact school/alias, then whole words, then word prefixes.
- **What migrates** (all in `~/Library/Application Support/MMTVL/`, saved by `App/JSONConfigFile.swift`):
  - **Keychain** (service `dev.mmtvl.launcher`, legacy login keychain): `iptv-playlist-url` (a URL string) and `iptv-guide-urls` (a JSON array, in priority order; the legacy `iptv-guide-url` is the fallback, `IPTVSourceStore.swift:7-11,36-56`).
  - `iptv-channels.json`: `{favorites, hiddenChannels, hiddenGroups, teams}` (`ChannelPreferences.swift:5-31`).
  - `epg-overrides.json`: `{overrideKey: lowercased EPG id or ""}`.
  - `iptv-state.json`: `lastChannelID`, `lastGroup`, `recentChannelIDs` (`IPTVState.swift:9-19`). Its `Date`s are **seconds since 2001-01-01** (add 978307200 for Unix time; `JSONConfigFile.swift:34-36`), though none of the migrated keys is a date.
  - `settings.json`: `channelUpMovesUpList` (default true), `usePlaylistGuide` (false), `teamMatchInitials` (false), `teamMatchNicknames` (false), `antennaEnabled` (true), `antennaGuide` (true) (`App/AppSettings.swift:23,41,83,86,89,92`).
  - **Not migrated:** `guide.sqlite`, `guideImports`, the Multiview snapshot, `antennaGuideDue`, logos.
- **Reusable on the Mac side:** `AVControl/ReceiverDiscovery.swift`, `SSDPSearch`/`SSDPSearcher` (:189-292), already does SSDP M-SEARCH. The script follows the same request format with `ST: roku:ecp`; the script is Python, so this is a reference, not shared code.
- **Tests to mirror:** M3UParserTests 12, ChannelListTests 6, ChannelLineupTests 16, XMLTVTests 9, EPGMatcherTests 14, EPGSuggesterTests 5, TeamMatcherTests 42, TeamCatalogTests 5, MyTeamsTests 14, LiveSearchTests 17, GuideModelTests 43, AntennaLineupTests 19, AntennaGuideTests 11. Their fixtures are inline Swift, with no fixture files.

### Roku platform (researched 2026-11-18; Roku's docs read as `developer.roku.com/dev/docs/<slug>.md`)

- **Developer mode and sideloading** ([developer-setup](https://developer.roku.com/dev/docs/developer-setup.md)):
  - Home ×3, Up ×2, Right, Left, Right, Left, Right. Then turn on the installer, set a password, and the Roku reboots. The web installer is at the device's address, user `rokudev`.
  - **One sideloaded app at a time**; uploading replaces it. User reports say it survives reboots. No expiry is documented.
  - Roku may disable dev mode for accounts that sideload content violating its terms ([forum](https://community.roku.com/t5/Roku-Developer-Program/Developer-Mode-Disabled-for-Accounts-Violating-the-EULA-and-or-Developer-Tools-Agreement/td-p/422114)).
- **Tooling** (npm and the VS Code Marketplace, 2026-11-18): `brighterscript` 0.73.8 (v1 still alpha), `roku-deploy` 3.18.4, `rooibos-roku` 5.17.0 (a bsc plugin; tests run **on the device**), `@rokucommunity/bslint` 0.8.47, `roku-debug` 0.24.7, and the VS Code "BrightScript Language" extension 3.0.1. Ports: the BrightScript console is 8085 and `chanperf` is on 8080 ([debugging](https://developer.roku.com/dev/docs/debugging.md)).
- **Video** ([video](https://developer.roku.com/dev/docs/video.md), [content-metadata](https://developer.roku.com/dev/docs/content-metadata.md), [media](https://developer.roku.com/dev/docs/media.md)):
  - `StreamFormat`: mp4, hls, ism, dash, mkv. HLS is AVC/HEVC, segments may be TS. `HttpHeaders` per content.
  - `StreamStickyHttpRedirects` exists, which implies redirects are followed (**unverified** for the provider's redirect; step 3).
  - `control="prebuffer"` for one stream at a time, `asyncStopSemantics` (OS 12.5+) for faster switching, and `playStartInfo` for timing.
  - **Live: stay at least 30 s from the live edge.** There's a pause buffer (`pauseBufferStart/End/Position/Overflow`) of undocumented size.
- **One video at a time:** a second playing `Video` fails with "player: only one playing instance supported" (errcode 16, Ultra 4850X, OS 14.6; [forum 2025-07](https://forum.developer.roku.com/t/roku-multiview/11357)).
  - `roMultiDecode` exists from OS 14.6, with **no public docs**; the forum's advice is Roku's developer beta program.
  - Fubo's Roku Multiview: 4 windows on an Ultra 4850X, 2 on an Express 4K+ / Stick 4K+, OS 14+, no player controls ([Fubo help](https://support.fubo.tv/hc/en-us/articles/30574847628045-How-does-Multiview-work-on-Roku)). Roku announced a multiview toolkit for third-party apps with no timeline ([Cord Cutters News](https://cordcuttersnews.com/rokus-new-build-your-own-multiview-feature-set-to-expand-to-more-apps-like-youtube-tv-sling-tv-hulu-live-more-after-fubo-launch/)).
  - The provider's own Roku app doesn't mention Multiview (its help page, checked 2026-11-18; not named here, see Hygiene).
- **Codecs and HDHomeRun:**
  - MPEG-2 isn't in Roku's media spec. Check at runtime with `CanDecodeVideo({codec:"mpeg2"})` ([ifDeviceInfo](https://developer.roku.com/dev/docs/ifdeviceinfo.md)).
  - AC-3 is device-specific (decode or passthrough). Check with `CanDecodeAudio`.
  - SiliconDust's Roku app needed an MPEG-2-capable Roku, now OS 13+, and later blacklisted the hardware MPEG-2 decoder, with weak deinterlacing ([Roku community](https://community.roku.com/discussions/apps-and-viewing/os-12-5-hdhomerun-malformed-data-error/928058)).
  - Roku staff (2014) said raw TS isn't a supported container ([forum](https://forum.developer.roku.com/t/how-to-use-h-264-ts-streams/3100)). **Whether `http://<tuner>:5004/auto/v5.1` plays is unverified** (step 3).
  - HDHR4 doesn't transcode (`?transcode=` is EXTEND-only, [HTTP API](https://info.hdhomerun.com/info/http_api)).
  - A busy tuner answers 503 with `X-HDHomeRun-Error` 805.
- **Data** ([ifUrlTransfer](https://developer.roku.com/dev/docs/ifurltransfer.md), [file-system](https://developer.roku.com/dev/docs/file-system.md), [roRegistry](https://developer.roku.com/dev/docs/roregistry.md), [memory-management](https://developer.roku.com/dev/docs/memory-management.md), [ifAppMemoryMonitor](https://developer.roku.com/dev/docs/ifappmemorymonitor.md)):
  - **There is no gunzip.** `EnableEncodings(true)` only handles HTTP `Content-Encoding: gzip`.
  - **There is no streaming XML parser.** `roXMLElement` parses the whole document in memory.
  - `AsyncGetToFile` writes a download to disk.
  - `cachefs:` is RAM per developer id, doesn't count toward app memory, holds "an arbitrary amount", and is evicted on reboot or under pressure. `tmp:` is cleared on exit and counts toward app memory.
  - **The registry holds 32 KB compressed** per developer id, survives reboots, needs `Flush()`, and `GetSpaceAvailable()` reports what's left. Deleting the dev app in the installer cleared its registry from OS 10.5 on ([forum](https://community.roku.com/t5/Roku-Developer-Program/In-OS-10-5-deleting-developer-channel-via-the-installer-clears-registry/td-p/727346)). **Whether replacing the build keeps it is unverified** (Q33).
  - Devices have 512 MB–2 GB, and an app over its limit is killed. Read the limit with `GetChannelMemoryLimit()`/`GetChannelAvailableMemory()` (OS 12.5+); alerts at 80–95 % from OS 15.2.
  - Some 512 MB devices run a 720p UI.
  - Another sideloaded IPTV app, AerioTV-Roku (v0.3.80), reports plain XML working with bounded, file-backed parsing, `.xml.gz` "not established", and no Multiview while `roMultiDecode` is unavailable ([release notes](https://github.com/EndofLineTech/AerioTV-Roku/releases/tag/v0.3.80)).
- **Threads** ([threads](https://developer.roku.com/dev/docs/threads.md), [data-transfer-apis](https://developer.roku.com/dev/docs/data-transfer-apis.md)):
  - Blocking the render thread for 3 s kills a sideloaded app.
  - Network calls and parsing belong in `Task` nodes. Calls into render-thread nodes from a Task wait for the render thread.
  - OS 15's `MoveIntoField`/`SetRef`/`roRenderThreadQueue` move big arrays without copying.
- **TimeGrid** ([timegrid](https://developer.roku.com/dev/docs/timegrid.md)):
  - Root → a ContentNode per channel (TITLE, HDSMALLICONURL) → a ContentNode per programme (TITLE, PLAYSTART, PLAYDURATION).
  - It has `contentStartTime`, `duration`, `maxDays`, `fillProgramGaps`, lazy loading feedback, a now bar and a Now/Next mode.
  - It's the only node that gets `channelup`/`channeldown`.
- **Keys** ([onKeyEvent](https://developer.roku.com/dev/docs/onkeyevent.md)): back, up, down, left, right, OK, replay, play, rewind, fastforward, options (`*`), and pause (with `pause_aware`).
  - **Home can't be caught.**
  - With the `Video` node focused, `*` opens the system overlay, so a parent group keeps focus.
  - Keyboards: `StandardKeyboardDialog` (with voice) and `DynamicMiniKeyboard` ([standard-keyboard-dialog](https://developer.roku.com/dev/docs/standard-keyboard-dialog.md)).
- **Deep links and ECP** ([deep linking](https://developer.roku.com/dev/docs/implementing-deep-linking.md), [roInput](https://developer.roku.com/dev/docs/roinput.md), [ECP](https://developer.roku.com/dev/docs/external-control-api.md)):
  - `Main(args)` gets `contentId` (at most **255 characters**) and `mediaType`. A running app gets `roInput` with `supports_input_launch=1`.
  - Discovery is SSDP `ST: roku:ecp` and answers with `Location: http://<ip>:8060/`.
  - `POST /launch/dev?contentId=…&mediaType=…` launches the sideloaded app; `POST /input?…` reaches a running one.
  - From OS 14.1, "Control by mobile apps" must be **Enabled** for keypresses and some queries. `launch` and `input` aren't on that list, so they should work under the default **Limited** (**unverified**; step 3).
- **Sockets:** `roStreamSocket.listen` is documented; `roDataGramSocket` handles UDP. Whether broadcast send (HDHomeRun discovery) works is **unverified**.
- **Outgoing:** HTTPS needs `SetCertificatesFile("common:/certs/ca-bundle.crt")`. User-Agent can be overridden. Plain http to LAN addresses isn't restricted.
- **UI:** `ui_resolutions=fhd` gives a 1920 × 1080 design space, scaled down on 720p devices. Fonts are bundled TTF/OTF. Use WebP and size images to what's shown (texture memory).

### Hygiene

- **Never write the provider's name, its domains, or its Roku app's name in committed files.** The public history was scrubbed of them (D34). Write "the provider" or `iptv.example`.
- No Roku address, serial, dev password or `DeviceAuth` in the repo. `roku/.env` is gitignored.

## Design

### Layout

```
roku/
├─ manifest                  title=MMTVL Live TV, ui_resolutions=fhd, supports_input_launch=1, pause_aware=1 (if it applies), bs_const=DEBUG=…
├─ bsconfig.json             BrighterScript; plugins: rooibos-roku (test builds only), bslint
├─ package.json / package-lock.json   devDependencies only (L1); scripts: build, lint, deploy, test, package
├─ .env.example              ROKU_HOST=, ROKU_DEV_PASSWORD=   (.env gitignored)
├─ source/
│   ├─ main.bs               Main(args): scene, roInput, migration launch args
│   └─ lib/                  pure logic, no nodes (portable, unit-tested):
│       ├─ M3U.bs            parse + ChannelList.make (ids as MMTVL)
│       ├─ Lineup.bs         groups, favorites/hidden/My Teams/Antenna order
│       ├─ XMLTVScan.bs      chunked scanner (no roXMLElement on whole guides)
│       ├─ XMLTVDate.bs, EPGMatcher.bs, EPGSuggester.bs
│       ├─ Inflate.bs        streaming inflate (only if step 4 keeps .gz)
│       ├─ TeamMatcher.bs, TeamCatalog.bs
│       ├─ SettingsStore.bs  registry schema v1 (L5)
│       ├─ Capabilities.bs   device class (D56)
│       └─ Log.bs            hosts-only logging (L6)
├─ components/
│   ├─ MainScene.xml/.bs     screen router: Player, Guide, Search, Settings, Import, Probes (DEBUG)
│   ├─ tasks/                PlaylistTask, GuideTask, LogoTask, AntennaTask, ImportTask
│   ├─ player/               PlayerScreen (Video in a focused Group), Banner, ErrorPanel
│   ├─ guide/                GuideScreen (GroupList + TimeGrid), ChannelMenu, MatchGuide
│   ├─ search/               SearchScreen (DynamicMiniKeyboard + results)
│   ├─ teams/                ChooseTeams (leagues → conferences → teams)
│   ├─ settings/             SettingsScreen and pages
│   └─ theme/                Theme.bs (tokens from DesignSystem/Theme.swift), 9-patch images
├─ data/                     pro-teams.json (golden, step 16); college-teams.json copied at build
├─ images/                   icons, splash (from Assets.xcassets/Logo), 9-patches (WebP/PNG)
└─ tests/                    Rooibos suites + fixtures/ (shared golden files, step 5)
scripts/roku-export-settings.py   one-time migration (L2), python3 -I, standard library only
```

### Data flow

1. **Launch:** `SettingsStore.load()` reads the registry, then `Capabilities.detect()` runs.
2. **Playlist:** `PlaylistTask` downloads the playlist, `M3U.parse` and `ChannelList.make` build the channels, and `Lineup.build` sorts them into the scene's `channels` field.
3. **Guide:** `GuideTask`, for each guide in priority order:
   1. `AsyncGetToFile` into `cachefs:/guides/<sha1>.xml(.gz)`.
   2. Inflate, if the file is `.gz` and that is enabled, streaming into `cachefs:`.
   3. `XMLTVScan` pass 1 reads the `<channel>` blocks (ids and display-names; small), then `EPGMatcher` decides the matched ids across all guides.
   4. Pass 2 reads `<programme>` blocks: it finds each `channel="…"` with native `Instr` and fully parses only the matched channels within `[now − 2 h, now + window]`.
   5. It returns `{channelID: [programmes]}` to the scene, moved, not copied, on OS 15.
4. **Refresh:** the playlist at launch and every 15 min while the app runs (D40's cadence); each guide when older than 12 h, at launch and every 15-min tick. After a Roku reboot, `cachefs:` is empty, so the guides download again.

### Local decisions

- **L1, tooling:** BrighterScript (`.bs`, namespaces and classes, compiled to BrightScript), `roku-deploy`, Rooibos and bslint as npm **devDependencies** in `roku/`. `package-lock.json` is committed. Nothing from npm ships in the app. The device address and password come from gitignored `roku/.env`.
  - *Why:* type checks and tests with no runtime dependency.
- **L2, migration** is a one-time script, `scripts/roku-export-settings.py` (Python standard library, run as `python3 -I`):
  1. Reads `iptv-playlist-url` and `iptv-guide-urls` with `security find-generic-password -s dev.mmtvl.launcher -a <account> -w` (macOS may ask to allow it), plus the JSON files above.
  2. Builds **bundle v1**: `{version:1, playlistURL, guideURLs[], usePlaylistGuide, favorites[], hiddenChannels[], hiddenGroups[], teams[], overrides{}, lastChannelID, lastGroup, recentChannelIDs[], channelUpMovesUpList, teamMatchInitials, teamMatchNicknames, antennaEnabled, antennaGuide}`.
  3. Finds Rokus by SSDP `roku:ecp` (or takes `--roku <host>`) and lists them by `query/device-info` name.
  4. Serves the bundle **once**, on an ephemeral port bound to the LAN interface, at `/<32 hex>` (128 random bits). It expires after 10 minutes; a second GET returns 404.
  5. Runs `POST http://<roku>:8060/launch/dev?contentId=mmtvl-import:<mac-ip>:<port>:<32hex>&mediaType=special`.
  6. The Roku's `ImportTask` GETs the bundle (LAN addresses only, at most 64 KB), validates it, and shows a summary (playlist host, number of guides and favorites, and so on) with **Replace Settings** / Cancel.

  It never prints a URL, token or secret, only hosts and counts. If the app is running, the same `contentId` comes in by `roInput`.

  - **Fallback:** Settings → Live TV Source and Guides take URLs through `StandardKeyboardDialog`; the Roku mobile app's keyboard can paste text into it (**unverified**).
  - *Why:* no change to MMTVL's app code, and no runtime link. Plain HTTP on the LAN is D11's trust level, with one GET and a 10-minute life.
- **L3, guide grid:** Roku's `TimeGrid`, with a `LabelList` group column on its left (Search, Favorites, My Teams, Antenna, All Channels, then the playlist's groups, looping like MMTVL's), and the channel menu as an overlay list.
  - *Why:* native performance on sticks, channel keys on Roku TVs, lazy loading. Custom styling is limited to what TimeGrid exposes, which the step 10 design accounts for.
- **L4, keys:** D49 carries over: **Back never leaves Live TV**, and Roku's Home is the only way out.
  - **Player:** Up/Down zap up/down the list, as MMTVL (`channelUpMovesUpList` flips only Channel Up/Down, on Rokus that send them; user, 2026-11-18); Left/Right do nothing; OK toggles the banner (or retries on the error panel); `*` opens the channel menu; **Replay** goes to the previous channel; Play/Pause pauses (Roku pause buffer); Rewind/Fast Forward skip 10 s within the live window (clamped 30 s from the edge); Back hides the overlays, else opens the guide.
  - **Guide:** OK plays; `*` opens the channel menu; Rewind/Fast Forward page by 6 rows (MMTVL's Channel Up/Down); Back closes the groups, then returns to the playing channel, and does nothing with nothing playing.
  - The `Video` node never has focus (so `*` reaches the app).
- **L5, storage:**
  - One registry section, `mmtvl`, written as one JSON value per key: `source` (playlist URL), `guides` (array), `prefs` (favorites, hidden, teams), `overrides`, `state` (last channel, group, recents), `settings`. A `schema` key holds 1.
  - Every save checks `GetSpaceAvailable()`. Under 4 KB left, Settings shows a warning, and saving the overrides refuses with a message instead of failing silently.
  - Guides, inflated files and logos live in `cachefs:` only.
- **L6, logging:** `Log.info(category, text)` prints `[MMTVL][<category>]`. Its URL helpers print **only the host**, never paths, queries, tokens, `DeviceAuth`, the migration secret, or the tuner's address. Release builds (`DEBUG=false`) print only warnings and errors.
- **L7, device classes (D56):** `Capabilities.detect()` gives:
  - `memoryMB` (`GetChannelMemoryLimit`);
  - `uiHD` (720p UI);
  - `mpeg2` (`CanDecodeVideo`), `ac3` (`CanDecodeAudio`);
  - `osVersion`, `model`.

  From these:
  - **Low** (≤ 512 MB limit class or a 720p UI): a 24 h guide window, no inflate for guides over 2 MB compressed, and the Antenna MPEG-2 channels hidden unless `mpeg2`. Channel logos stay **on** (a toggle in Settings → Device). On a Low Roku's first launch, a **low-memory notice** (shown once, remembered in `state`) names the features that are on and may slow it (Channel Logos, plus any step 4 adds) and offers OK / Open Settings (Settings → Device) (user, 2026-11-21).
  - **High:** a 36 h window, logos on, inflate allowed (if step 4 keeps it).

  The thresholds come from step 4's measurements. Settings → Device lists each item with *On*, or *Off: <reason>*.
- **L8, the Probes screen** exists only in `DEBUG` builds (`bs_const`), opened by a key sequence on the About page. Its results are console lines prefixed `[PROBE]`.

## Implementation steps

Every step runs `cd roku && npm run build` (bsc, no errors) and `npm run lint` before it hands back, and the MMTVL build still passes where it's touched. Roku steps with logic also run their Rooibos suites on the device (`npm test`, which needs `roku/.env`). When no device is reachable, QA runs build and lint only, and the device run moves to the next `[human]` step.

### Phase 0 — device and probes

- [ ] **1. Device setup** `[human]`
  - Get a **Roku Ultra (4850X or newer)** as the reference. Fubo's Multiview needs one, so it's the device on which `roMultiDecode` is worth probing. Also a **Streaming Stick or Express** for the low-end checks (a 512 MB model, ideally one with a 720p UI).
  - Turn on developer mode (Home ×3, Up ×2, Right, Left, Right, Left, Right), set the installer password, and give the Roku a DHCP reservation.
  - Copy `roku/.env.example` to `roku/.env` and fill it in.
  - Record each device's model, Roku OS version, and Settings → System → Advanced → Control by mobile apps setting under *Deviations & questions*.
  - Optional: apply to Roku's developer beta program for `roMultiDecode` documentation (Q30).
  - Done when: the installer page loads in a browser with the password, and the record is in this plan.
- [x] **2. Scaffold** `[implementer]`, files: `roku/**` (layout above), `.gitignore` (`roku/.env`, `roku/out/`, `roku/node_modules/`)
  - npm scripts:
    - `build`: bsc into `out/staging`, then a zip in `out/`.
    - `lint`: bslint.
    - `deploy`: roku-deploy with `.env`.
    - `test`: a Rooibos build, deploy, then reads results from port 8085.
    - `console`: `nc $ROKU_HOST 8085`.
  - A `MainScene` that shows "MMTVL Live TV" and the version.
  - An app icon and splash from the `Logo` asset (exported PNGs: `mm_icon_focus_fhd` 540 × 405, splash 1920 × 1080).
  - Done when: `npm run build` and `npm run lint` are clean; with a device, `npm run deploy` shows the scene and one passing Rooibos sample test. `git status` shows no `.env` or `node_modules`.
- [x] **3. Probes build** `[implementer]`, files: `roku/components/probes/**`, `roku/source/lib/Inflate.bs` (first version), `roku/source/lib/XMLTVScan.bs` (first version)

  DEBUG-only (L8). Each probe logs `[PROBE] <name> <result>` and never a URL. Test URLs are typed into the Probes screen, or come through the migration contentId as a test, never committed.
  - **a. HLS start:** play one provider channel URL. Log the time from `control=play` to `state=playing`, whether the redirect was followed, and the time for a second channel with `prebuffer` and `asyncStopSemantics`.
  - **b. Antenna:** `CanDecodeVideo` for mpeg2 and h264, `CanDecodeAudio` for ac3. Play `http://<tuner>:5004/auto/v<n>` for an H.264 channel and an MPEG-2 one, with `streamFormat` `hls`, `mp4`, then `mkv` and unset (whatever plays), and log the state or error. Check that interlaced 1080i shows without combing.
  - **c. Multiview:** start a second `Video` while the first plays and log the error. Log `CreateObject("roMultiDecode")` (invalid or a type) and `GetInterface` names if it exists.
  - **d. Inflate:** time `Inflate.bs` on a 110 KB guide (FANDUEL1) and on US2 (6.5 MB), streaming from `cachefs:` to `cachefs:`. Log bytes/s, peak memory (`GetChannelAvailableMemory`) and the total time. Stop after 10 minutes.
  - **e. Scan:** time `XMLTVScan` over a plain 77 MB XML in `cachefs:` (served by `python3 -m http.server` on the dev Mac from a gunzipped copy), with 60 matched channel ids. Log the time, programmes kept and peak memory. Also log whether `AsyncGetToFile` of 77 MB into `cachefs:` succeeds on each device.
  - **f. Discovery:** a `roDataGramSocket` broadcast of SiliconDust's discover packet on 65001, plus `hdhomerun.local` resolved by `roUrlTransfer`. Log found or not.
  - **g. Registry:** write `probe=<build time>`. On the next sideload, log whether it survived (Q33).
  - **h. Limits:** log `GetChannelMemoryLimit`, the UI resolution, model and OS.
  - **i. ECP:** the dev Mac runs `curl -X POST "http://$ROKU_HOST:8060/launch/dev?contentId=probe&mediaType=special"` while the app runs and while it doesn't. Log whether `roInput` or `Main(args)` got `contentId`.
  - **j. Guide variants (dev Mac, by the user):** for each of the user's guide URLs, check whether the host also serves the plain `.xml` (`curl -sI` with the URL minus `.gz`). Only the result goes in this plan (yes/no and the size), **never the URL**.
  - Done when: it builds, the Probes screen lists the probes, and each probe runs without crashing the app on the dev's device.
- [ ] **4. Probe results and decisions** `[human]`
  - Run step 3 on the Ultra and the stick. Record a table of the numbers here.
  - **The user decides:**
    - **.gz guides on the device:** keep inflate where it finishes US2 in under ~3 min on the Ultra and doesn't exceed memory; otherwise plain `.xml` only, or a guide left out with a message.
    - **The guide window per class**, from e.
    - **Antenna:** H.264 only, or MPEG-2 too where `mpeg2` and b play.
    - **Multiview:** M13 if c shows `roMultiDecode` usable (or Roku's beta docs arrive), else drop.
  - Update D55/D56 and Q30–Q33 in the master plan accordingly.
  - Done when: the table and the decisions are in *Deviations & questions*, and the master plan matches.

### Phase 1 — data and logic

- [x] **5. Parity fixtures** `[implementer]`, files: `roku/tests/fixtures/{playlist.m3u, channels.golden.json, guide-a.xml, guide-b.xml, matches.golden.json, overrides.json}`, `MMTVLTests/RokuParityTests.swift`
  - Hand-written fixtures, with no real URLs or provider names, covering:
    - the M3UParserTests and ChannelListTests cases: BOM, CRLF, `#EXTGRP`, VOD filtering, duplicate ids `#2`, `-H`/`-A` feeds, missing names;
    - EPGMatcherTests' rules: override, `""`, tvg-id, normalized names, guide priority.
  - `RokuParityTests` (Swift Testing) loads the fixtures through `#filePath`, runs `M3UParser`/`ChannelList.make`/`EPGMatcher`, and `#expect`s equality with the golden JSON. This keeps MMTVL and the Roku app in step.
  - Done when: `xcodebuild … test -only-testing:MMTVLTests/RokuParityTests` passes and the full MMTVL suite passes (quote the result line).
- [x] **6. M3U and channels** `[implementer]`, files: `roku/source/lib/M3U.bs`, `roku/tests/M3UTests.bs`
  - A port of `M3UParser.parse` and `ChannelList.make`/`feedName` (rules in *Research*).
  - Done when: `M3UTests` reproduce `channels.golden.json` exactly, plus the M3UParserTests cases as Rooibos tests (12).
- [x] **7. Settings store and capabilities** `[implementer]`, files: `roku/source/lib/SettingsStore.bs`, `Capabilities.bs`, tests
  - L5 and L7. Defaults equal MMTVL's (`channelUpMovesUpList` true, and so on). The registry size check works as L5 says.
  - Done when: tests cover round-trips, defaults for missing keys, a corrupt value reading as the default, and the low-space refusal (with a fake space function).
- [x] **8. Playlist and lineup** `[implementer]`, files: `roku/components/tasks/PlaylistTask.*`, `roku/source/lib/Lineup.bs`, tests
  - Fetch with the CA bundle (and http), at most 4 MB.
  - The host is logged as MMTVL does: "Loaded N channels from <host>".
  - On failure, keep the last channel list in memory and show "Couldn't load the playlist (<host>)".
  - Refresh at launch, every 15 minutes, and when the guide opens if older than 10 minutes.
  - `Lineup.build`: the groups in MMTVL's order (Favorites with live team games on top once step 18 lands; until then, saved favorites), hidden channels and groups removed, All Channels.
  - Done when: `LineupTests` mirror the ChannelLineupTests cases (16), and with a device, the console shows the load line with only the host.
- [x] **9. Guide pipeline** `[implementer]`, files: `roku/components/tasks/GuideTask.*`, `roku/source/lib/{XMLTVScan,XMLTVDate,EPGMatcher,Inflate}.bs`, tests
  - D55 as decided in step 4. Up to 6 guides plus the playlist's `url-tvg` rule (`usePlaylistGuide`).
  - Per guide, the status (OK, N channels matched / Can't read .gz on this Roku / Too large for this Roku / Failed: <host>) is kept for Settings → Guides.
  - Memory guard: stop a guide when `GetChannelAvailableMemory` drops under 15 % of the limit, and mark it "Too large for this Roku".
  - Done when:
    - `XMLTVTests` (the 9 Swift cases, including `xmltv_ns`, `onscreen`, missing stop, merged ids, 16 names) and `EPGMatcherTests` (14) pass as Rooibos tests;
    - `matches.golden.json` is reproduced;
    - with a device, FANDUEL1-sized and US2-sized fixtures (generated, not real) finish within step 4's numbers.

### Phase 2 — UI

- [x] **10. The Roku look** `[designer]`
  - In the user's pen.dev, design the player banner (channel, number, logo, now/next with times and progress), the error panel, the guide (group column plus TimeGrid in its styleable fields), the channel menu, Search, Choose Teams, Settings rows, the Import confirm screen, and Settings → Device.
  - Base them on MMTVL's Live TV and `DesignSystem/Theme.swift` tokens. SceneGraph has no blur, so glass is 9-patch translucent panels with a rim; the banner role (D46) is a darker, more opaque panel.
  - Make a 720p check of type sizes (FHD scaled down).
  - Then write `roku/components/theme/Theme.bs` (colors, fonts, sizes) and the 9-patch images.
  - **The user picks** before steps 11–13 build the screens.
  - Done when: the user has approved a frame for each screen, and `Theme.bs` builds.
- [x] **11. Player** `[implementer]`, files: `roku/components/player/**`, `MainScene`
  - L4 player keys.
  - The banner shows on a channel change and on OK, and hides after 5 s.
  - Paused overlays fade after 15 s (D51).
  - The error panel ("Can't play this channel", OK retries) appears on a `Video` error or a stall over 15 s.
  - Keep the last channel and recents (10) in `state`.
  - At launch, open the last channel full screen if there is one, else the guide.
  - Done when: `PlayerKeyTests` (a key-to-action table: zap direction, Replay, Back states) pass, and with a device, zapping and Back show as L4 says.
- [x] **12. Guide** `[implementer]`, files: `roku/components/guide/**`
  - L3 and L4 guide keys.
  - TimeGrid fed lazily, per visible channel, from the GuideTask results; "No guide" rows for unmatched channels.
  - Channel logos through `LogoTask` (cachefs, off on low devices).
  - The channel menu: Watch, Add/Remove Favorites, Move Up/Down (Favorites), Hide Channel, Match Guide (step 20).
  - Remember `lastGroup`.
  - The guide returns to the playing channel after 3 minutes without a press (D51).
  - Done when: `GuideKeyTests` (the GuideModelTests cases that apply: group looping, Search above the groups, Back states, paging by 6) pass, and with a device, the guide opens in under 2 s with the guide loaded.
- [x] **13. Settings** `[implementer]`, files: `roku/components/settings/**`
  - Pages:
    - **Live TV Source:** shows the playlist's host only; Change… opens the keyboard.
    - **Guides:** up to 6, add/remove/reorder, status per guide, Use the Playlist's Guide.
    - **Groups & Hidden Channels.**
    - **Channel Up direction.**
    - **My Teams** (step 18).
    - **Antenna** (step 21).
    - **Import from MMTVL:** how to run the script.
    - **Device** (L7).
    - **About:** version and build.
  - URLs are never shown whole: host, plus a guide file name when it looks like one (M6b L2's rule).
  - Done when: each page saves through `SettingsStore` and survives a relaunch (device), and `SettingsPageTests` cover the URL display rule.

### Phase 3 — migration

- [x] **14. Export script and import** `[implementer][security]`, files: `scripts/roku-export-settings.py`, `scripts/test_roku_export_settings.py`, `roku/components/tasks/ImportTask.*`, `roku/components/import/**`, `roku/source/main.bs`
  - L2 end to end.
  - **The script:**
    - `--dry-run` prints the bundle's summary (counts and hosts only).
    - `--roku <host>` skips SSDP.
    - It refuses if the Roku host isn't a LAN address.
    - It exits after one GET or after 10 minutes.
  - **The Roku:**
    - parses `mmtvl-import:<ip>:<port>:<hex32>` strictly (a private IPv4 address, the port, 32 hex);
    - fetches at most 64 KB;
    - validates every field's type, length (URLs ≤ 2 KB, ≤ 6 guides, ids ≤ 256 characters, ≤ 500 entries per list) and http(s) scheme;
    - shows the summary, and **Replace Settings** writes the store and reloads the playlist and guides.
  - Done when:
    - `python3 -I scripts/test_roku_export_settings.py` passes: bundle building from fixture files with a fake Keychain reader, 2001-epoch dates ignored, the single-use server, the secret format, and nothing secret on stdout;
    - Rooibos `ImportTests` (contentId parsing, rejecting public/loopback hosts and malformed bundles, the size cap) pass;
    - a security review (`security-reviewer`: the one-time URL, logs, input validation) has no open findings.
- [ ] **15. Device build A** `[human]` (Ultra and stick; the receiver at −75 dB, the TV and receiver off when done)
  1. Run `python3 -I scripts/roku-export-settings.py`, pick the Roku, and confirm on the TV. Favorites, hidden channels and groups, last channel and the guides show as on MMTVL.
  2. Zap through 10 channels and record start times. Banner, pause/resume, Replay, Back → guide → Back → the same channel, Home leaves.
  3. For each guide, record its status on Settings → Guides and how many channels have a guide, against MMTVL's count.
  4. Leave it playing 30 minutes on the stick. No crash; record `chanperf` (`nc $ROKU_HOST 8080`, `chanperf`) memory at start and end.
  5. Reboot the Roku, open the app: guides download again, and settings are kept.
  6. Re-sideload a build: are the settings kept (Q33)?
  - Done when: each check is ticked or its failure is recorded here, with the console lines (hosts only).

### Phase 4 — teams, search, Match Guide

- [x] **16. Teams data** `[implementer]`, files: `roku/data/pro-teams.json`, `roku/bsconfig.json` (copy `../MMTVL/IPTV/Teams/college-teams.json` into the package at build), `MMTVLTests/RokuParityTests.swift`
  - A Swift test checks that `TeamCatalog`'s pro teams serialize exactly to `roku/data/pro-teams.json` (id, league, name, nickname, aliases, abbreviations), so the golden file can't drift.
  - The college catalog is loaded lazily in a Task (382 KB).
  - Done when: the parity test passes, and the package contains both files (`unzip -l out/*.zip`).
- [x] **17. TeamMatcher port** `[implementer]`, files: `roku/source/lib/TeamMatcher.bs`, `TeamCatalog.bs`, `roku/tests/fixtures/teams.golden.json`, tests
  - Game entries ("Away @ Home", not in "…Replay…" groups), programme matching (pro full name, nickname + league word; college "A at B" exact school, the description's first sentence by linear scan, aliases, nickname appended, apostrophes dropped), the Match Initials and Match Nicknames Alone switches, and `upcomingGames`.
  - Fixtures carry over the TeamMatcherTests (42) and MyTeamsTests (14) cases. The Swift side checks `teams.golden.json` too (in `RokuParityTests`).
  - Done when: both sides pass the golden file, and on a device, matching 100 channels' now-programmes takes under 500 ms on the stick (console timing).
- [x] **18. My Teams** `[implementer]`, files: `roku/components/teams/**`, `Lineup.bs`, guide
  - The My Teams group: Choose Teams… (leagues → conferences → teams, as M7l), live games, up to 30 upcoming games in 3 days (OK tunes), live team games on top of Favorites.
  - Recomputed after playlist and guide loads, after a team is picked, and every 5 min.
  - The channel menu's Add/Remove … to My Teams for pro game entries and programmes, pro and college (the picked team first, at most 3 a side, as MMTVL's `menuTeamsPerSide`; not college game entries). Mirrors MyTeamsTests' `theChannelMenuOffersEachSidesTeamsPickedFirst` and `…AtMostThreeTeamsASide` (amended at step 17, see *Deviations*).
  - Settings → My Teams: the picked teams and both Matching switches.
  - Done when: `MyTeamsLineupTests` pass, and on a device, picking a team that's playing shows its game in My Teams and atop Favorites.
- [x] **19. Search** `[implementer]`, files: `roku/components/search/**`
  - A Search row above the groups (as MMTVL).
  - A `DynamicMiniKeyboard`, results from 2 characters: 8 channels (folded substring), 12 teams (MMTVL's ranking; OK adds or removes the team and keeps search open), 40 programmes in the next 24 h (every word in the title).
  - Debounced 300 ms in a Task.
  - Done when: `SearchTests` mirror LiveSearchTests (17), and on a device, results update while typing without dropping key presses on the stick.
- [x] **20. Match Guide** `[implementer]`, files: `roku/source/lib/EPGSuggester.bs`, `roku/components/guide/MatchGuide.*`
  - Channel menu → Match Guide: Automatic, No Guide, then ranked suggestions (an `EPGSuggester.rank` port over the channel names collected in pass 1).
  - A choice writes `overrides` (keyed by the channel name; antenna channels by id) and re-runs matching without downloading.
  - Done when: `EPGSuggesterTests` (5) pass, and on a device a match survives a relaunch.

### Phase 5 — antenna (as decided in step 4)

- [x] **21. Antenna** `[implementer][security]`, files: `roku/components/tasks/AntennaTask.*`, `roku/source/lib/{HDHomeRun,AntennaLineup,AntennaGuide}.bs`, Settings → Antenna, tests
  - **Discovery:** the methods that passed probe f, then an address typed in Settings → Antenna (LAN addresses only). `discover.json` is accepted only from a private address, with `BaseURL` = that address.
  - **Lineup:** `lineup.json`, leaving out DRM and disabled entries; ids `antenna:<GuideNumber>`; the **Antenna** group after My Teams and at the end of All Channels; `displayNumber`.
  - **Playback:** per step 4. MPEG-2 channels are hidden with "Some antenna channels need MPEG-2, which this Roku can't play" on Settings → Device when they can't play.
  - **Tuners:**
    - The app counts its own streams. 503/805 shows "Both antenna tuners are in use".
    - It reads `status.json`/`lineup_status.json` for "No signal on this channel" and "The tuner is scanning for channels".
    - It never prefetches.
  - **Guide:** SiliconDust's, per probe (the XMLTV through `GuideTask` if it's gzip-encoded in transit or inflate is kept; otherwise its JSON guide, **unverified**), daily at most, with `DeviceAuth` read fresh from `discover.json` into a local and **never logged or stored**. No channel scan on Roku (MMTVL or the tuner's own page does that).
  - Settings → Antenna: Use Antenna, Guide from SiliconDust, the tuners found (name, model, tuner count), Find Tuners, Address.
  - Done when: `AntennaLineupTests` mirror the Swift cases that apply (19), `AntennaDiagnosisTests` pass, and the security review of the discovery and `DeviceAuth` handling has no open findings.

### Phase 6 — low-end tuning, review, docs

- [ ] **22. Low-end pass** `[implementer]`
  - Memory alerts (OS 15.2: `roAppMemoryNotificationEvent`) drop logos and shrink the guide window.
  - The texture budget: logos at their display size, WebP.
  - The 720p layout check, and the Settings → Device texts.
  - Done when: on the stick, a 2-hour run with guide browsing stays under 80 % of `GetChannelMemoryLimit` (console line every 5 min, DEBUG).
- [ ] **23. Device build B** `[human]` (Ultra and stick)
  1. My Teams: pick a pro and a college team that are playing. Both appear in My Teams and atop Favorites, and upcoming games tune.
  2. Search: a channel, a team (add/remove), a programme.
  3. Match Guide on an unmatched channel. It survives a relaunch.
  4. Antenna: channels listed, an H.264 channel plays, MPEG-2 per step 4, both tuners busy gives the message (start 2 antenna streams elsewhere).
  5. The stick: an hour of use without a crash, and the Settings → Device texts are right.
  - Done when: each check is ticked or its failure is recorded here.
- [ ] **24. Security review** `[security]`
  - The whole `roku/` tree and the script: no URL, token, `DeviceAuth` or secret in logs; the import's validation; LAN-only rules for import and antenna; HTTPS certificate use; the registry contents; the npm devDependencies (versions, `npm audit`, nothing shipped); gitleaks (`scripts/gitleaks.toml`) over the branch; no provider name.
  - Done when: no open findings above low, and lows are recorded here.
- [ ] **25. Docs** `[doc]`
  - A **Roku (M12)** section in `CLAUDE.md`:
    - the commands: `npm run build|lint|deploy|test|console` in `roku/`, `.env`, the migration script and its flags;
    - the layout; the registry section `mmtvl` and its keys;
    - the `cachefs:` use;
    - the log prefix `[MMTVL][<category>]` and the never-log rules;
    - the parity tests;
    - the device classes;
    - the "provider name never committed" rule.
  - `roku/README.md`: dev mode, sideloading, migration, what's off on low-end Rokus, and that the app is unofficial and personal.
  - The master plan: M12's status, D54–D56 as built, Q30–Q33.
  - Done when: the docs match what was built (the `npm` scripts named exist).

## Tests

- **Rooibos (on the device)**, in `roku/tests/`: M3UTests, LineupTests, SettingsStoreTests, CapabilitiesTests, XMLTVTests, EPGMatcherTests, InflateTests (if kept), PlayerKeyTests, GuideKeyTests, SettingsPageTests, ImportTests, TeamMatcherTests, MyTeamsLineupTests, SearchTests, EPGSuggesterTests, AntennaLineupTests, AntennaDiagnosisTests.
- **Swift:** `MMTVLTests/RokuParityTests`: channels, matches, pro teams and team matches against `roku/tests/fixtures/*.golden.json` and `roku/data/pro-teams.json`.
- **Python:** `scripts/test_roku_export_settings.py`.
- **Commands:**
  - `cd roku && npm run build && npm run lint && npm test`
  - `python3 -I scripts/test_roku_export_settings.py`
  - `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`

## Manual verification

Steps 4, 15 and 23 on the devices (three device sessions: probes, build A, build B). TV etiquette as the MM's (memory: receiver at −75 dB during tests; TV and receiver off when done).

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| On-device inflate too slow or too big for US2 | Probe d: > 3 min or memory alerts | Plain `.xml` if the host serves it (probe j); else that guide is listed "Can't read .gz on this Roku" and its channels show "No guide" (the user accepted on-device only). |
| A 77 MB plain XML doesn't fit `cachefs:` or scans too slowly on the stick | Probe e | A shorter window, or stream-scan while downloading in ranges (`Range` headers, if the host supports them); otherwise the guide is "Too large for this Roku". |
| Raw TS from the tuner won't play | Probe b | Antenna limited to what plays, or left out with a Settings → Device note (Q31). |
| `roMultiDecode` not available to a sideloaded app | Probe c, no beta docs | No Multiview on Roku; M13 is dropped (Q30). |
| Registry wiped on re-sideload | Probe g, Q33 | Document "run the export script again after reinstalling"; the import is quick. |
| ECP launch blocked under Limited | Probe i | The script tells the user to set Control by mobile apps to Enabled for the import, then back. |
| Roku disables dev mode | The installer page is gone | The app has no store path; out of our hands. |
| MMTVL's matching changes later | `RokuParityTests` fails | Update the golden file and the Roku port together. |
| A public host the playlist names (a `url-tvg` guide, a stream, an HLS sub-resource) redirects the Roku to loopback, ECP or a LAN device. `roUrlTransfer` follows redirects itself and the `Video` node fetches HLS sub-resources itself, so `URLPolicy` judges only the first URL, and MMTVL's relay-level hop checks (D39) can't be matched | Security review of step 8 (M-1, 2026-11-18) | **Accepted residual: a blind GET only** (ECP's state-changing commands are POST). After each fetch, `roUrlEvent.GetTargetIpAddress()` is checked with `URLPolicy.allowsPeer`, and the body is discarded when a public chain ended on an internal address (whether it reports the last hop is a device check). Use the Roku on a trusted network. |
| Developer mode exposes the app to the LAN: the BrightScript console on port 8085 has no authentication (Ctrl-C breaks into the debugger, where the registry can be read), and dev-mode ECP queries may show node fields | Security review of step 3 (M-1, 2026-11-18); check `curl http://<roku>:8060/query/app-ui` and port 8085 on the first device session | Inherent to sideloading. Use the Roku on a trusted network only (README and tester instructions say so). The probe build erases typed URLs when Probes closes. The app never puts a URL in a node field it doesn't need, and the risk is re-assessed in step 24. |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.

- **2026-11-18, all device steps (1, 3, 4, 15, 23, and the "with a device" parts of other steps): no Roku here; a remote tester has one.** The user has no Roku. Test builds go to a remote tester, model unknown, who uses the **same provider** with their **own playlist**, typed in on the Roku. No Mac with MMTVL is on the tester's network. User decisions (2026-11-18):
  - **Off-device logic tests.** `brs-node` (an npm devDependency, an off-device BrightScript interpreter) runs the tests for the pure logic in `source/lib/` on this Mac with `npm run test:local`. That is the QA gate for the `lib` steps. Rooibos suites stay for node and key logic, run whenever someone has a device on the LAN. Every "pass as Rooibos tests" in steps 6–9, 17 and 19–21 is met by `test:local` for `lib` code.
  - **The probe build reports on screen.** The Probes screen shows a results table the tester photographs, plus a short summary code the user pastes back. It never shows a URL. Console `[PROBE]` lines stay. This changes L8.
  - **Big-guide probes (3d, 3e) don't need the dev Mac.** The probe generates a synthetic US2-sized XMLTV in `cachefs:` (77 MB, about 80,000 programmes) to time the scan, and inflate is timed on a small synthetic `.gz` in the package. In addition, the tester can type one of their own guide URLs (same provider, so likely US2 itself) for a real download, inflate and scan.
  - **Not testable remotely, deferred until the user has a Roku on their own network:** migration (step 14's device part, step 15.1), probe 3i (ECP launch needs a computer on the Roku's network), and 3j's `curl` (the user can run 3j on this Mac at any time, since it needs only the guide URLs). Probe 3b (antenna) runs only if the tester has an HDHomeRun.
- **2026-11-18, step 2 (done; QA PASS, build/lint/test:local clean, no device run).** As built, beyond the layout:
  - `roku/tools/roku.mjs` runs `deploy`, `test`, `console` and `test-local`, reads `roku/.env` (a one-line message and exit 1 when it's missing), and passes the password to Rooibos by environment, never argv.
  - The Rooibos build is `bsconfig.test.json` (extends `bsconfig.json`, specs staged as `source/tests`). The off-device build is `bsconfig.local.json`. Local suites are `tests/local/<Suite>.test.bs` with `namespace <Suite>Tests` and `sub test_<name>(t)`, run by `tests/local/support/LocalTest.bs`, and `npm run test:local` exits 1 on any failure. `npm run lint` covers all three projects.
  - Also: HD icon and splash variants, and `bs_const=DEBUG=true` in the manifest. **The release build must set DEBUG=false** (QA minor): owed by whichever step adds packaging; no `package` script yet.
  - **`npm audit`: 43 high, accepted as dev-only.** zod via brs-node's jimp, picomatch (no patched release exists) and decode-uri-component. Nothing from npm ships in the app (L1). Re-check at step 24.
  - Device checks owed to the first device session: `npm run deploy` shows the scene and version, the icon and splash look right, and the Rooibos sample passes.
- **2026-11-18, step 3 review (security L-2), carried to steps 6, 8, 9 and 21:** the app fetches whatever the playlist names: its `url-tvg` guide, and its stream URLs. Carry over the equivalent of MMTVL's `RelayURLPolicy`, so public entries never reach loopback, link-local, LAN or the Roku's own addresses.
- **2026-11-18, step 3, for step 9: display-name case.** Step 3's `XMLTVScan` lowercases display-names, as *Research* says, but MMTVL's `XMLTVParser.add` keeps names as written, de-duplicated exactly. So "ESPN" and "espn" stay two names when ids merge. Matching folds case either way. Step 9 follows MMTVL, and the parity fixtures decide.
- **2026-11-18, step 3 (done; QA PASS, security review: 1 medium + lows, all fixed or carried).** Built as the deviations above say: the Probes screen (DEBUG only, OK or `*` on the main scene) with on-screen results, a details page and a summary code. Typed entries go in registry section `mmtvl-probe` and are erased when Run all ends or the screen closes, and a release build deletes that section at launch. The own guide is the typed one, else the playlist's `url-tvg` (`src=typed|tvg|-`). `npm run build:release` (`bsconfig.release.json`, DEBUG=false) checks itself for probe code. `source/lib/Inflate.bs` checks ISIZE, not CRC-32 (too slow per byte in BrightScript; add `GetCRC32` per piece if step 4 keeps inflate), and `XMLTVScan.bs` exists in its first version. `test:local`: 40 passed, 0 failed. Fixes: QA Q1–Q4 (raw memory-call values with types in h, a "guard inactive" note, `xmltv_ns` empty parts as in Swift, a permanent 256 KB inflate test) and security M-1, L-1, L-3, L-4, L-6, L-7. Accepted: L-5 (dotless names pass `safeText` in error text only) and L-8 ("US2" is a guide file name, already in the plans).
  - **Not verified (device):** everything the probes measure; the units of the `ifAppMemoryMonitor` calls; `ReadFile`/`AppendFile` with offsets; whether `cachefs:` holds 77 MB; `roDataGramSocket` broadcast; `StandardKeyboardDialog`; whether `ToAsciiString` decodes UTF-8; whether a stopped Task keeps running.
- **2026-11-18, step 5 (done; QA PASS).** `RokuParityTests`: 5 tests. Full suite: "2091 tests in 186 suites passed". Fixtures: `playlist.m3u` (43 entries, 36 channels, BOM then CRLF then LF, kept by `roku/tests/fixtures/.gitattributes`), `guide-a.xml`, `guide-b.xml`, `overrides.json`. Goldens, Unix seconds UTC with explicit nulls:
  - `channels.golden.json`: `guideURLs`, every parsed `entries` item including VOD, `feedNames`, and `channels`.
  - `matches.golden.json`: channel id → `{guide, file, epgID}` or null.
  - `programmes.golden.json` (added for step 9): per guide, `wantedIDs`, `channels` and `programmes`.

  Regenerate with `TEST_RUNNER_MMTVL_WRITE_ROKU_GOLDENS=1 xcodebuild … -only-testing:MMTVLTests/RokuParityTests`. Settled for the ports:
  - display-names keep their case; only a merge de-duplicates them, and repeats within one `<channel>` stay;
  - the override key is the shown name, after `feedName`;
  - lowercasing is Unicode (step 6 must check BrightScript's `LCase` on non-ASCII).

  Carried: the `antenna:` override key goes to step 21. A malformed XMLTV file throwing needs a plain test in step 9, since a golden can't express it.
- **2026-11-18, step 6 (done; QA PASS).** `source/lib/M3U.bs` (`parse`, `makeChannels`, `feedName`, `groups`, `readFile`) reproduces `channels.golden.json` exactly. All 12 M3UParserTests and 6 ChannelListTests cases are in `tests/local/M3U.test.bs`. New file `source/lib/Unicode.bs` (`Unicode.lower`, `trim`, `isExtend`); any component that loads `M3U.bs` also needs it.
  - **Lowercasing:** whether Roku's `LCase` handles non-ASCII is undocumented, so ids lowercase through an explicit table that matches Swift for U+00C0–U+052F (generated, tested over the whole range).
  - **URLs are kept as written**, with no percent-encoding or punycode. `M3U.isValidURL` approximates which URLs Swift's `URL(string:)` refuses; ids don't depend on it.
  - **Fixtures:** the local build stages `tests/fixtures/**` as `pkg:/fixtures/` (`brs-cli -r`), and the app zips have none.
  - **Moved to step 8:** `guideGroups` and `channels(in:)` from ChannelListTests.
  - **Device checks:** what `LCase`, `ReadAsciiFile` (BOM, UTF-8), `Len`/`Mid` and `roRegex` actually do, and parse time on the stick. brs-node: 5,000 entries take 0.7 s to parse plus 0.5 s to build channels.
- **2026-11-18, step 7 (done; QA PASS, majors fixed).** `source/lib/SettingsStore.bs` (L5) and `Capabilities.bs` (L7), with 85 local tests at that point.
  - **The registry is injected:** `read`, `write`, `delete`, `flush`, `spaceAvailable`.
  - **QA fixes:** every save checks the value's size against the space left. A save that won't fit gets a "too large" message and writes nothing, and overrides keep 4 KB free. `save` and `replaceAll` are all or nothing, putting the old values back on a failed write or flush. Override keys are lowercased, and on a collision the last in sorted order wins.
  - **Deviations:** `lastChannelID` and `lastGroup` use `""` for none. Sizes are estimated uncompressed, which is conservative against the 32 KB compressed budget; revisit with real `GetSpaceAvailable` numbers. The memory-limit unit is guessed from its magnitude, provisionally, until step 4. The thresholds are named constants.
  - **bsc gotcha:** inside a namespace, a local variable named like a function of that namespace is rewritten to the function. Avoid such names.
- **2026-11-18, step 8, decisions on the implementer's questions:** stream URLs are checked by step 11's player **as MMTVL does**: http(s), and the entry's own host is allowed whatever it is. `GuideTask` (step 9) checks typed guides with no referrer and `url-tvg` guides with the playlist as referrer, then checks the peer address with `URLPolicy.allowsPeer`. Step 12's guide calls `refreshPlaylistIfStale()` when it opens. **Security L-3 is open:** the root scene's `lineup` and `playlistGuideURLs` fields hold token-bearing URLs. Decide after the first device session checks whether dev-mode ECP `/query/app-ui` or `/query/sgnodes` shows node fields; if it does, keep URLs in `m` and expose only ids.
- **2026-11-18, step 8 (done; QA PASS, security review: 1 medium (accepted residual, Risks table) and 7 lows, fixed except L-3 and L-6).** `test:local`: 155 passed.
  - **New `lib` code:** `Lineup.bs`, a port of `ChannelLineup`, `guideGroups` and `channels(in:)`, with all 16 ChannelLineupTests cases plus 2 ChannelListTests cases. `Lineup.build(channels, prefs, liveTeamChannelIDs)` takes the live team channel ids; upcoming games wait for step 18. Antenna channels are those with `source: "antenna"` and a `guideNumber` (step 21).
  - **`URLPolicy.bs`:**
    - `allows(url, referrer)` judges the first URL. With a referrer, the host must be plain ASCII with no empty label, and a host whose last label is a number must read as IPv4 (WHATWG's rule, narrower than review L-2 as written, so `cafe.be` passes).
    - `allowsStream(url)` accepts any http(s) host, as MMTVL does.
    - `allowsPeer(ip, publicChain)` judges the address a fetch actually reached.
    - `allowsInChain` is the full MMTVL rule, kept for if redirect hops ever become visible.
  - **`Refresh.bs`:** `isDue` and the cadence and timeout constants.
  - **`PlaylistTask`:** http(s) only, the CA bundle, a 4 MB cap, a 30 s timeout, try/catch around the body, and host-only logs. It logs whether `GetTargetIpAddress` reported a peer (a device check). Its `url-tvg` guides are filtered with the playlist as referrer.
  - **MainScene:** loads the settings registry, loads the playlist at launch and every 15 min (`refreshPlaylistIfStale()`), has a 60 s watchdog, and keeps the last list when a load fails.
  - **`Log.host`** returns "" for an authority with a backslash, space or control character.
  - **Device checks:**
    - the "Loaded N channels from <host>" line;
    - whether the 4 MB cap applies while downloading (does `tmp:` grow?);
    - what `GetTargetIpAddress` reports, and for which hop;
    - what `GetIPAddrs` returns;
    - that the watchdog and the 15-minute timer fire;
    - that try/catch works in a Task thread;
    - lineup build time on the stick.
- **2026-11-18, step 9 (done; QA PASS ×3, two security reviews with all mediums fixed).**
  - **Pure logic:** `XMLTVScan` at parity with MMTVL, `XMLTVDate`, `EPGMatcher` (with a Foundation fold table generated by `roku/tools/gen-epg-fold.swift`), and `GuidePipeline`, which matches across all guides and keeps only the winners' programmes. It reproduces `matches.golden.json` and `programmes.golden.json` exactly.
  - **Task side:** `GuideSources.bs` (source choice as MMTVL's, cache names by SHA-1, `.time` and `.fail` in wall-clock seconds), `GuideFetch.bs` (limits, memory guard, status rows), `FieldMove.bs`, `components/tasks/GuideTask.*`, and the MainScene wiring.
  - **Caps and limits (provisional until step 4):**
    - downloads: 120 MB per file and 300 MB of cachefs per run;
    - time: 180 s per download, 600 s to read the guides;
    - memory: stop at 15 % left, or when held data × 2 exceeds what's left;
    - text: titles 400 UTF-16 units, desc 1,000, display-names 200;
    - programmes: 300 per channel; in total 60,000 (High) or 25,000 (Low), shown as "OK, N channels matched (guide shortened)".
  - **Retries:** a failed guide waits 1 h; a refused or too-large one waits 12 h. A changed channel set reruns matching at most hourly, and a failed run backs off 1 h.
  - **Hand-off:** the scene keeps the finished task as `guideHolder`. Step 12 reads `guideHolder.guideData` once per `guideRevision`.
  - **URL checks:** typed guides `allows(url)`, `url-tvg` guides `allows(url, playlistURL)`, then `allowsPeer` on the reported peer. `EnableEncodings` stays off.
  - **`Log.host`** returns "" for scheme-less, over-long or non-ASCII hosts, and `Log.withHost` drops the "()".
  - **For step 13:** Settings must refresh the scene's `m.store`, or call `refreshGuideIfDue()`, after saving guides or `usePlaylistGuide`. Otherwise the scene and the task disagree on the source set.
  - **Noted, no change:** security L-7 (a crash backtrace on port 8085 shows locals; re-check in step 24) and L-8 (unsalted SHA-1 of guide URLs in file names; readable only with dev-mode access).
  - **Device checks:**
    - FANDUEL1- and US2-sized timings;
    - cachefs subfolders, `Rename`, and whether files survive a reboot;
    - `GetTargetIpAddress`;
    - `GetChannelAvailableMemory` units against the guard;
    - `MoveIntoField` on OS 15;
    - a Task stopping on `control="stop"`, and seeing `cancel`;
    - how `Len`/`Asc` treat non-BMP text;
    - the copy cost of reading `guideData`;
    - the watchdogs and back-offs in the log.
- **2026-11-18, phase 2 start (orchestrator).** No device yet (the remote tester's model is still unknown), so phase 2 is built off-device and every "with a device" check moves to step 15. Order within the phase: step 10's frames and step 11–13's pure logic run in parallel (the logic as `lib` namespaces with `test:local` suites: `PlayerKeys`, `GuideKeys`, `URLDisplay`), then the screens after the user picks the frames. The design file is new: `design/roku-live-tv.pen`, committed like the code.
- **2026-11-18, steps 11–13 logic (QA PASS; user decisions).** `PlayerKeys.bs`, `GuideKeys.bs` and `URLDisplay.bs` with `test:local` suites (29, 34 and 11 tests; 338 in all), ported from LiveTVModel, GuideModel and GuideSource and their tests. The user decided where MMTVL and L4 disagreed:
  - **Zap:** as MMTVL. Up is always up the list, and `channelUpMovesUpList` flips only Channel Up/Down. L4 is amended.
  - **Skips:** as L4. Rewind/Fast Forward skip 10 s, clamped 30 s from the live edge. Left/Right do nothing in the player (MMTVL's 10/30 split isn't used; the 40 s window would clamp 30 s skips).
  - **Replay** (L4 only) goes to the most recent other channel, so A→B→Replay→Replay alternates.
  - In the guide, Rewind/Fast Forward and Roku's channelup/channeldown page by 6 rows (the group column by 7, as MMTVL).
  - `URLDisplay` is stricter than MMTVL (only printable-ASCII escapes are decoded, hosts are lowercased, a refused host shows "?" alone). Accepted.
  - Left for later: `setLineup` (keep group and row across a refresh) at step 12, and My Teams' upcoming rows at step 18.
  - **Device checks:** that Back from the player and guide never reaches the scene; whether channelup/channeldown reach a non-TimeGrid node; what `pauseBufferStart/End/Position` hold before the clamp is trusted; that `Chr(183)` shows as a middle dot.
- **2026-11-18, step 10 (part done; blocked on Pencil).** `roku/components/theme/Theme.bs` (`Theme.make()` → colours, fonts, layout, images, timing; MMTVL token names where one exists; the minimum type size is 24 px, which is 16 px at 720p; Roku system fonts, nothing bundled) and 9 nine-patches in `roku/images/` (panel, banner-role panel, settings row, focus row and capsule, guide cell, guide focus filled (A) or ring (B), bar), made by `python3 -I roku/tools/gen-ninepatch.py`.
  - **Frames not drawn:** this session's Pencil MCP was the VS Code bridge, with VS Code not running.
  - **Frames to make:** Banner A (full-width bottom panel, MMTVL) and B (compact bottom-left card, now/next in two columns), the error panel, Guide A (filled focus) and B (ring focus), the guide with the group column open, the channel menu, Search, Choose Teams, Settings → Live TV (source host, guides with status), Settings → Device, Import confirm, 720p copies at 2/3, and a notes frame mapping colours and fonts to fields.
  - **TimeGrid styling (Roku docs):** text colours and font, one `programBackgroundBitmapUri` for every cell (so no per-cell colour), `focusBitmapUri`, the time bar and now bar bitmaps, colours and sizes, `channelNoDataText` ("No guide") and `fillProgramGaps`, and the channel column as a custom component (`channelInfoComponentName`, `channelInfoWidth` 340, `infoGridGap` 12). Row height and visible rows aren't documented fields (**unverified**, device check in step 12).
  - **Other nodes:** the group column is a LabelList with `vertFocusAnimationStyle="fixedFocusWrap"` for the looping groups. DynamicMiniKeyboard can only be styled through its palette.
  - **Deviation:** settings rows have a 32 px radius for one- and two-line rows (MMTVL: a capsule, or 40 for two-line rows); one 9-patch can't do both at 72 px.
- **2026-11-21, step 10 (frames drawn; user choices).** The Pencil MCP now runs Pen desktop's server, set as a project-local override (`claude mcp add pencil -s local -- /Applications/Pen.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-arm64 --app desktop --agent claudeCodeCLI`). **Pencil can't create a `.pen` file, and it writes to whichever document is in front.** So the user made `design/roku-live-tv.pen` in Pen (File › New, Save As) and left it in front; the designer checked the target before every write and save.
  - **Frames:** Banner A/B, error panel, Guide A/B, group column open, channel menu, Search, Choose Teams, Settings, Import confirm, 720p checks and a notes frame (Theme.bs tokens → SceneGraph fields).
  - **Theme.bs additions:** `focusedWarningText`; images `panel_solid` (menus over the guide: the 0.82 panel let guide titles show through without blur), `settings_info_row` (Rectangles can't round corners), and the gradients `overlay_bottom` and `background`, all from `gen-ninepatch.py`.
  - **User choices:** **Banner A** (full width, as MMTVL). **Guide A** (filled white focus cell, black title). **Settings exactly as MMTVL's Settings** ("it should be set just like it is in the full swift version"): D42's layout, and a root of categories (Live TV, Remote & Input with only Channel Up, then the Roku-only Device and Import from MMTVL, and About). The Live TV page uses MMTVL's sections, wording and footers (Playlist, Guides with a page per guide, Channels, Manage); keyboard rows replace paste rows, and there's no Preview on Home. **This changes step 13's page list:** step 13 builds what the Settings frames show.
  - **Not possible in SceneGraph as drawn** (in the notes frame): Video corners are square; TimeGrid has one cell background, no tick lines, and `showPastTimeScreen` must be false; DynamicMiniKeyboard styles only through its palette; the 1.03 focus scale needs an Animation; `blendColor` alpha on the opened row is **unverified**. Icons `icon_warning.png` and `icon_check.png` are still to make (steps 11, 18). Montserrat stands in for Roku's system font.
  - **Device checks (step 15):** text widths in the system font, 720p legibility of dimmed values, `panel_solid` opacity on a TV, TimeGrid's real row height.
  - **Approved (2026-11-21):** all frames as drawn after the Settings redo, which mirrors MMTVL. Root: Live TV, Remote & Input, Device, Import from MMTVL, About. Live TV page: Playlist, Guides, Channels, Manage, with a page per guide. Roku-only wording: "Change Playlist URL…", "Add Guide…", "Added Guides", "press * on it", and the Manage footer. Every layout value in Theme.bs, the 9-patches and the frames is on Roku's **3-px grid** (FHD→HD is 2/3; Roku's display-resolution doc), with type ≥ 24 px.
  - **Channel Logos (user, 2026-11-21):** "toggle, but leave it on by default … a banner on initial launch … Any other features for low memory devices that might create issues can be included in this banner too." This amends L7 and D56: logos are on everywhere, and a first-launch **low-memory notice** on Low Rokus points to Settings → Device. It's a new frame; step 11 or 12 builds it (whichever screen opens first).
  - **4K Rokus:** Roku's UI sizes are SD, HD and FHD only, so a 4K Roku shows the FHD layout scaled up; video plays at 4K. How a 4K Roku scales the UI isn't in the doc (**unverified**); look at it on a 4K Roku in step 15. 720p images for HD devices (the doc recommends them) go to step 22.
- **2026-11-21, step 11 (built; QA PASS, minors only).** Added: `PlayerScreen`, `PlayerBanner` (Banner A), `ErrorPanel` and `LowMemoryNoticeView`, plus pure logic in `PlayerSession`, `BannerText` and `LowMemoryNotice`. `tools/gen-icons.py` makes `icon_warning.png`. MainScene is now the screen router. `test:local`: 373 passed.
  - **Decisions:**
    - The notice flag is `state.lowMemoryNoticeShown`. `settings.channelLogos` defaults to true. Both are Roku-only, and an import keeps them.
    - A stream that reports "finished" counts as a failure.
    - Logos are checked like `url-tvg` guides (`URLPolicy.allows(logo, playlist)`).
    - A failed first playlist load opens the guide, as MMTVL does.
  - **Placeholders:** the guide and Settings → Device are simple stand-ins in MainScene until steps 12 and 13. Their literal y values go with them. The player's `*` only logs until step 12's channel menu.
  - **Open, user choice 2026-11-21:** paused and skipped video gets a **Roku timeshift bar designed like MMTVL's** (the bar, the behind-live badge, the paused symbol), drawn by the designer and then built as **step 11b**. Until then the overlay timing exists with nothing drawn, so the first Back or OK after a pause hides an invisible overlay.
  - **Orchestrator decisions:**
    - Back on the low-memory notice counts as OK. It dismisses the notice for good, as a modal's Back does, and never leaves the app. Built in step 11b.
    - The notice doesn't show when every listed feature is already off.
    - **For step 12:** the guide and the player must share one copy of the guide data, not one each (a Low Roku would hold the programmes twice). Channel logos go through `LogoTask` and cachefs, the player's banner included.
    - Step 12's Back must retry a failed channel (MMTVL), which needs the player to report when its error panel is up.
  - **Security L-3 grows:** stream and logo URLs are now also in the `Video` content, `PlayerScreen.channel`, `Poster.uri` and the banner's `info`. Re-assess with the device's `/query/app-ui` answer (step 15) and in step 24.
  - **Device checks (step 15):** zapping, Replay, Back states, and that Back never exits; whether the `Video`'s own UI shows without focus; pause and the `pauseBuffer*` fields; the 15 s stall; https streams with `HttpCertificatesFile`; logos over https; the →, · and – glyphs in the system font; banner times in local time; launch routing; the notice on a Low Roku; registry writes on every zap; the 720p layouts.
- **2026-11-21, step 11b (built; QA PASS).** `Timeshift.bs` is a port of MMTVL's `Timeshift`: the track is `pauseBufferStart`→`pauseBufferEnd`, and the labels read "LIVE", "−m:ss" or "−h:mm:ss". New `TimeshiftBar`. The player owns one banner panel for Banner A and the bar, and the behind-live badge sits top right. Back on the low-memory notice answers OK. `test:local`: 383 passed.
  - **Decisions:** the gradient always starts 120 px above the panel (MMTVL's rule), so it's shorter behind Banner A alone than in frame tpzUV. "Live" uses Roku's 30 s live-edge margin (`PlayerKeys.liveEdgeMarginSeconds`), not MMTVL's 15 s. Missing `pauseBuffer*` fields show "LIVE", with no fill and no badge.
  - **Device checks (step 15):** what `pauseBufferStart`, `pauseBufferEnd` and `position` hold, and whether they update while paused (both 0 would fill the whole track); how close to `pauseBufferEnd` a Roku plays; the U+2212 glyph; badge widths; the fades; and the 720p bar.
- **2026-11-21, step 12 (built; QA PASS after two fix rounds).** Added `GuideScreen` (a MenuListView group column and TimeGrid, with `GuideChannelCell` as its channel column), `ChannelMenuView`, `MenuListView` and `LogoTask`, plus pure logic in `GuideReader`, `ChannelMenu`, `GuideIdle` and `LogoCache`, and additions to `GuideKeys`. `test:local`: 427 passed.
  - **Shared guide data:** GuideScreen is the only reader. It does one plain field get per `guideRevision`. The player's banner and the channel menu get one channel's list through `callFunc("programmesFor")`; `PlayerSession.programmesFor` moved into `GuideReader`.
  - **Back:** Back retries a failed channel. It uses the player's new `failed` field, set while the error panel is up.
  - **Logos:** LogoTask fetches the newest request first and keeps at most 120 waiting. It answers a request it drops, so the guide can ask again when the row comes back into view.
  - **QA fixes:**
    - The group column keeps focus when the lineup or the guide refreshes while it is open (`GuideKeys.gridReport`, `pendingFor`).
    - Back or Left from the column lands on the programme cell.
    - Only key presses and the user's own focus moves restart the 3-minute idle return.
    - ChannelMenu's visible rows come from Theme.
    - GuideScreen reads the lineup once per change.
  - **Orchestrator decisions:**
    - "Fed lazily": each open builds a ContentNode for every row of the group, but programmes only for the focused row −6/+12.
    - Match Guide's menu row is left out until step 20.
    - The group column shows 8 rows (frame lB8XX) and pages by 7 (MMTVL).
    - The step needed MainScene, PlayerScreen, LogoTask and `lib` beyond `components/guide/**`.
  - **Reference:** Roku's TimeGrid doc returned 403, so the fields were checked against brs-node's TimeGrid. `rowHeight` and `numRows` are set only if the node has them.
  - **Device checks (step 15):**
    - **TimeGrid's channel cell and wrapping:**
      - the interface `channelInfoComponentName` gets;
      - whether TimeGrid wraps vertically, and the rows near the end (`GuideReader.fillRange` clamps);
      - whether it takes or passes channelup/channeldown;
      - that `*`, Back and Rewind/FF reach GuideScreen;
      - that children added after `content` is set are drawn.
    - **TimeGrid's focus reports:**
      - whether `jumpToChannel` reports synchronously or later, and whether it reports at all when focus doesn't move;
      - whether `focusIndex` counts gap cells (`fillProgramGaps`).
    - **Times in TimeGrid:**
      - **`playStart` is Float per roku-types**: epoch seconds in a 32-bit float step by 128 s, so cell edges may be off; check, and if so use `contentStartTime`-relative values;
      - the real row height and visible rows.
    - **Speed:**
      - the guide opens in under 2 s on All Channels;
      - `Lineup.build` on the render thread after a favorites edit.
    - **The column:**
      - with the column open, a lineup refresh keeps Up/Down in the column;
      - Back lands on the programme cell;
      - the info area matches the highlight.
    - **Logos:**
      - with a slow logo host, rows scrolled to arrive first, and dropped rows fill in after scrolling back;
      - logos over https into cachefs.
    - **Other:**
      - the 3-minute return;
      - the Video in the preview place;
      - `callFunc` with no arguments;
      - the `‹`, `…` and `·` glyphs.
- **2026-11-21, step 13 (built; QA PASS after two fix rounds).** Settings is built to the approved frames (LQwUy, wjg72, DEDBc, B94oz), with MMTVL's wording where the frames don't say. New: `SettingsScreen`, and pure `SettingsPages`, `SettingsStatus`, `SettingsNav`, `SettingsEdits` and `GuideRuns`; `SettingsStore.saveMany` (all or nothing); `GuideFetch.statusRows` gains a per-guide `programmes` count; `Capabilities.modelName` (`GetModelDisplayName`). `test:local`: 497 passed.
  - **Orchestrator decisions:**
    - **Opening Settings:** `*` in the guide's group column, or in a guide with no rows (so a first launch without a playlist can reach it). This contradicts MMTVL's `menuInTheGroupsColumnDoesNothing` (GuideModelTests.swift:327), deliberately: the Roku has no home screen with a Settings tile. Back from the root returns to where Settings opened.
    - **The Channels footer** reads "To favorite or hide one channel: in the guide, press * on it." until step 20, which restores the frame's "favorite, hide or match". The frame's Antenna and My Teams rows come with steps 21 and 18.
    - **"Add Playlist URL…"** when no playlist is set. Typed-URL errors are new text. Refresh Now forces every guide to download again.
    - **Animation:** only the track slides (outCubic, 0.4 s). Rows are clipped at the track's edges rather than faded, and the title, band and dimming change at once. Step 22 may revisit.
    - **Probes** (L8) open with three Replays on About, in DEBUG builds only; the guide's Replay route is gone.
    - **Device:** Compressed Guides follows `GuideSources.inflateEnabled`. A Roku that is Low only for its 720p UI reads "Low (720p UI)". The L5 low-space warning is the This Roku section's footer.
    - Left as is: a playing channel's sound continues under Settings; a refused-save message stays in the band until the page changes.
  - **QA fixes:**
    - The first playlist answer no longer pulls Settings away: the launch channel waits until Back (`PlayerSession.launchRoute`, `returnFromSettings`).
    - A guide run asked for during another run (a playlist change, Remove then Add, Add Guide, Refresh Now) runs right after it, with a pending delete first (`GuideRuns`).
    - The watchdog path keeps those requests.
    - Groups and Hidden Channels edits made during a playlist load survive it (a prefs revision).
    - Remove Live TV Source saves both addresses at once.
  - **Accepted (QA minor):** after the 2× watchdog give-up, the delete of `cachefs:/guides` can run while the abandoned task is still alive, and a late write can leave a guide file for the removed source until the next prune. It's the same accepted risk as step 9's security M-3; the files hold XMLTV data under SHA-1 names, no URL or token.
  - **Security L-3 tally:** the keyboard dialog's `text` holds a typed URL while typing; the scene reads it once and clears it, and clears it on close. Guide cache ids (unsalted SHA-1, L-8) now also appear in `SettingsScreen.model` and row ids. No new interface field holds a URL.
  - **Reference:** `StandardKeyboardDialog` fields were checked against roku-types (bundled with BrighterScript), not the live doc.
  - **Device checks (step 15):**
    - **The keyboard dialog:** typing; pasting from the Roku mobile app; focus back on Settings after OK, Cancel and Back.
    - **Keys:**
      - Back never exits;
      - `*` from the column and from an empty guide;
      - Replay ×3 on About (DEBUG);
      - whether held keys repeat without a release.
    - **Layout:**
      - `clippingRect`;
      - the slide at 1080p and 720p (frame E2Hjc4);
      - `blendColor` on the parent's selected row;
      - `boundingRect` widths and wrapped footers in the system font;
      - the `›` and `·` glyphs.
    - **Saving and reloads:**
      - each page's save survives a relaunch (the step's done-when);
      - Channel Logos off and on redraws the guide and the banner;
      - a new playlist loads and its guide match reruns;
      - Refresh Now re-downloads the guides;
      - Remove stops playback and empties `cachefs:/guides`, also during a guide run;
      - Settings opened during the launch load stays, and Back plays the last channel or opens the guide.
    - **Speed:**
      - Groups and Hidden Channels with hundreds of rows (built eagerly);
      - `Lineup.build` on the render thread when an edit lands during a playlist load.
    - **Device page:** `GetModelDisplayName` and the OS text on a Low and a High Roku.
- **2026-11-21, step 14 (built; QA PASS; security review: no open findings after two fix rounds).** New: `scripts/roku-export-settings.py` and its tests (40), `ImportBundle.bs` (pure: contentId, file cap, validation, summary), `ImportTask`, `ImportConfirmView` (frame NgJ0S), and the import route in `MainScene` and `main.bs` (`roInput` now in every build). `test:local`: 525 passed.
  - **Decisions:**
    - The secret is 32 **lowercase** hex (`secrets.token_hex`); the Roku refuses uppercase.
    - L2's limits: the **Roku rejects** a bundle that breaks any limit, or has a missing or unknown field; the **script trims** to the same limits first and prints what it left out, so a normal export always passes.
    - The legacy Keychain account `iptv-guide-url` is read when `iptv-guide-urls` is missing (`IPTVSourceStore.swift:39-40`).
    - The one-shot server answers **only the chosen Roku's address** (refused at accept, before any byte is read); stricter than L2.
    - Loading ("Getting the settings from the Mac…", Cancel) and failure (a message, OK) are drawn in the confirm panel; the frame shows only the confirm state. Back is Cancel, or OK when that's the only button. Replace Settings is focused first, as drawn.
    - Replace stops the playing channel and re-runs the launch target with the new playlist. A cold-launch import holds the launch target until it closes. A second import while one is open is ignored.
  - **Security fixes:**
    - **M-1:** a fake Roku could answer SSDP with the real one's name (and serial) and collect the bundle. The script now tells the user to check the **IP address** against Roku Settings → Network → About (a fake can't show the real address: LOCATION must equal the SSDP source, and the TCP connections go there), shows each serial's last 4, and warns when two entries share a serial or an NFKC/casefolded name.
    - **L-1:** a slow client held the single-threaded server past 10 minutes. Now `ThreadingHTTPServer`, other addresses refused at accept, an absolute deadline per connection, and `claim()`/`outcome()` under one lock (no double serve; expiry and a claim can't both win).
    - **L-2:** a malformed reply crashed the script with raw terminal escapes. `ecp_launch` maps `HTTPException` to a host-only error; `device_info` is a raw socket with one 5 s deadline and a strict status line; names and serials pass `clean_name`.
  - **Accepted (Low):** L-3, any LAN host with ECP can open the confirm screen with its own bundle and press Select (ECP can already type the same URLs into Settings; a bundle can set nothing typed Settings can't). L-4, the 64 KB cap is polled every 250 ms, so a hostile server can write ~0.25 s of data to `tmp:` before the cancel (deleted on every path). Also: a connection flood from a refused address could delay the Roku's connect (default backlog 5); a picked host can stall the script by trickling its ECP reply; many fake SSDP answers slow the listing.
  - **Unverified:**
    - Whether `roUrlTransfer` follows redirects (Roku's ifUrlTransfer doc returned 403; roku-types lists no setting). The defence is `GetTargetIpAddress` = the Mac's address; an empty address is accepted.
    - Whether a cancelled `AsyncGetToFile` can write once more after `tmp:/mmtvl-import.json` is deleted.
    - `ParseJson` key case on a device; `roInput` deep links in release builds (probe i covered DEBUG).
  - **Device checks (step 15):** discovery and the list (names, serial suffixes, addresses against Settings → Network → About; device-info has `serial-number`); the confirm screen at 1080p and 720p (wrapped question and footnote, truncated values); Replace (favorites, hidden channels and groups, last channel and guides as on MMTVL; Channel Logos and the low-memory notice state kept); Cancel changes nothing; import on a cold launch and while running; Back never leaves; a second run while the screen is up is ignored; expiry after 10 minutes shows "Couldn't get the settings"; the ECP 403 hint ("Control by mobile apps"); the `[MMTVL][Import]` lines, and a test server that answers 302.
  - **QA note:** QA's first local run didn't stub the device-name lookup and sent one read-only `GET /query/device-info` to a LAN address before it was stopped.
- **2026-11-21, step 16 (done; QA PASS).** `roku/data/pro-teams.json`: the 124 pro teams of `TeamCatalog`, in catalog order. It's a top-level array of objects with exactly `abbreviations`, `aliases`, `id`, `league`, `name`, `nickname`, sorted keys and the step 5 encoder, the same shape as `college-teams.json` minus `school` and `conference`, so step 17 reads both with one loop. It's written by `RokuParityTests` (`TEST_RUNNER_MMTVL_WRITE_ROKU_GOLDENS=1 xcodebuild … -only-testing:MMTVLTests/RokuParityTests`, which rewrites all goldens) and checked by `proTeamsMatchTheGolden`. MMTVL full suite: 2092 tests in 186 suites passed.
  - **Packaging:** `college-teams.json` is copied from `../MMTVL/IPTV/Teams/` to `data/college-teams.json`. This is in `bsconfig.json`, `bsconfig.test.json` and `bsconfig.release.json` (each lists its own `files`), and the file isn't committed twice. A single-file `src` needs the full `dest` path; `"dest": "data"` fails with EPERM. `build:release` fails if either data file is missing (now 95 files). `bsconfig.local.json` is unchanged; step 17 adds `data/` if its tests need it.
  - **Loading** is left to step 17: nothing reads `pkg:/data/` yet. **Unverified:** `ParseJson` of the 382 KB college file within a Low Roku's memory and time (step 17's console timing, step 15/23 on a device).
- **2026-11-22, step 17 (built; qa-deep PASS, minors only).** New: `TeamCatalog.bs` (reads and validates both catalogs with Swift's decode rules; a missing or bad file gives no teams of that kind and MMTVL's logged error), `TeamMatcher.bs` (the index, game entries, programme matching, the summary lead by linear scan, both switches, `upcomingGames`, the 400/4096-unit caps), `roku/tools/gen-team-tables.swift` (Unicode tables written between markers; idempotent), `teams.golden.json` (293 cases, written only by Swift), `MMTVLTests/RokuTeamsGolden.swift` (the golden's types, cases and an evaluator that calls the app's own code) and two `RokuParityTests`. `bsconfig.local.json` stages `data/`. MMTVL full suite: 2094 tests passed; `test:local`: 535.
  - **Coverage:** TeamMatcherTests (42) has 34 cases carried in full, 3 as the matcher part only, and 5 not carried. MyTeamsTests (14) has 2 in full, 7 as the matcher part only, and 5 not carried. The tests not carried cover lineup, preferences JSON, `IPTVLibrary` ordering and cancellation, guide keys and UI strings, which belong to step 18. Their matcher results are in the "matcher part only" cases. The fuzz test uses the same seed with 100 leads, and cancellation uses 50 programmes. qa-deep mutated the code 9 times and the golden once, and each mutation failed the Roku suite; a mutated golden failed the Swift test.
  - **Folding:** Swift's `normalized` differs from EPGMatcher's table at 92 BMP code points, which are now handled by generated tables. ICU's `\d`, `\w` and `\s` are reproduced by tables (`\s` = `Unicode.isSpace(_, true)`). The golden checks 3,722 code points.
  - **Decisions:**
    - The index is built in `TeamMatcher.bs`, as in Swift.
    - There's no `TeamsTask` yet; step 18 adds it.
    - The 30-game cap stays in the lineup (`ChannelLineup.maxUpcomingTeamGames`, `ChannelPreferences.swift:62,100`), so step 18 adds it.
  - **For step 18 (orchestrator, agreeing with qa-deep):**
    - Build only the index for the current Matching options, in the Task, at launch and when an option changes; the newest change wins, like `applyTeamMatchOptions`.
    - Keep the index and all matching inside the Task and return only ids or games, since assigning an index AA to a field deep-copies it.
    - A switch costs a rebuild on the Roku, where Swift has the index cached; that's acceptable.
    - Search and Choose Teams (step 19) need the team list separately; search doesn't use the index.
  - **Plan amended:** step 18's channel menu offered Add/Remove "for pro entries" only. MMTVL also offers college programme teams there (the picked team first, 3 a side), so step 18's item now says so.
  - **Accepted (minor):** `Unicode.isExtend` (`Unicode.bs:180-191`) knows only Latin combining marks. A 400-unit cut inside an Arabic, Hebrew, Indic or Thai mark lands one character later than Swift's (qa-deep reproduced it for U+064B, U+05B7, U+093F, U+0E31). A team name would have to straddle unit 400 for it to matter. Fix if it ever does: a Grapheme_Extend + SpacingMark table from `gen-team-tables.swift`, and a golden case with U+064B at unit 400.
  - **BrighterScript trap:** a local variable that has the same name as a function in its namespace is silently rewritten to that function, e.g. a local `words` became `TeamMatcher.words`. Rename such locals and check the compiled `.brs`.
  - **Off-device timing (brs-node, not representative):** catalog read 143 ms (1,431 teams); index 740 ms, or 1,567 ms with both options on; matching 100 channels 101 ms.
  - **Device checks (step 15/18):** the DEBUG lines `Teams: matched … in X ms` (under 500 ms for 100 channels on a stick), `Teams: indexed …` and `Teams: read 1307 college teams in X ms` on a Low Roku. Also check whether a Roku's `LCase` changes any non-ASCII character Swift leaves alone, and `prefix`, `foldNonASCII` and `leadState` on the Roku's UTF-8 strings.
- **2026-11-22, step 18 (built; qa-deep FAIL, then PASS after one fix round).** New:
  - `TeamsTask`: one for the app's life. It holds the index in its own `m`. With teams picked it builds the index at launch, otherwise when first needed.
  - Pure `MyTeams.bs` (the menu teams, texts and request serials), `TeamsWork.bs` (the queue, `match` = `updateTeams`, `menuSides`) and `TeamPicker.bs` (order identical to Swift's `localizedStandardCompare` on all 1,428 lines).
  - `ChooseTeamsView` (frame P9pORE) and `icon_check.png`.
  - Lineup, guide, channel menu, Settings and scene changes.
  - `test:local`: 566 passed; release: 105 files.
  - **Decisions:** D1–D6 in [M12-decisions-log.md](M12-decisions-log.md): MMTVL's leagues, not the frame's; the short-lived guide copy in the Task; the index at launch only with picks; the Channels footer waits for step 20; a one-line upcoming cell; the wording the frames don't show.
  - **QA fixes:**
    - The channel menu kept the row focused when it opened, rather than the live one, when the team rows arrived (`ChannelMenu.withItems`, `ChannelMenuView.replaceItems`).
    - Match and menu answers shared one field and could collapse into one; they now have separate `matchAnswer` and `menuAnswer` fields.
    - `forgetTeamResults` advances the match serial.
    - A failed catalog showed "Loading teams…" forever; it now says "Teams couldn't be loaded" and retries on the next open.
    - The `guideData` single-reader comments are corrected.
    - A DEBUG timing line around the guide read.
  - **Accepted (minor):** if `answerMenu` throws while it is being answered mid-match, that menu gets no team rows (reopening asks again). The removed-row clamp path in `withItems` isn't tested; QA read the code and judged it correct.
  - **Device checks (step 15/23):**
    - **The done-when:** a picked team that's playing shows its game in My Teams and on top of Favorites. Saved favorites are unchanged, and Move Up/Down shows only below the games.
    - **The guide and picker:** OK on an upcoming game tunes its channel. Choose Teams… opens the picker; Back steps back through it and never leaves Live TV; the 3-minute idle return closes it.
    - **The picker's look** at 1080p and 720p: columns, dimming, check marks (`blendColor`), "Loading teams…" on a cold open. A toggle survives a relaunch, in the order added.
    - **Channel menu team rows:** how late they arrive the first time, and that a row moved to before they arrive stays focused. Long titles truncate in the 720-wide menu.
    - **Settings → My Teams:** both switches change My Teams after a rebuild.
    - **DEBUG lines:** "Teams: read the guide (N programmes) in X ms", "Teams: read … teams", "Teams: indexed …" (at launch with picks), and "Teams: matched … in X ms" (under 500 ms for 100 channels). The 5-minute tick doesn't redraw the guide when nothing changed. A Low Roku with teams picked shows no stall or memory warning.
    - `GetDayOfWeek()` after `ToLocalTime()`; the `›` and `–` glyphs.
- **2026-11-22, step 19 (built; qa-deep PASS with minors, all fixed).** New:
  - `LiveSearch.bs` (pure: folding, channels, team ranking, the title index, `searchProgrammes`, the model, keys and texts);
  - `SearchTask` (the title index, once per guide load; newest query wins);
  - `SearchView` (frame rucDX, with a `DynamicMiniKeyboard`);
  - TeamsTask's `search` kind (queue: menu, search, catalog, match);
  - `GuideScreen.programmeDetails` / `focusChannel`, and `GuideKeys.focusChannel`.

  `test:local`: 594 passed; release: 110 files. LiveSearchTests (17): 11 in full and 6 as their pure parts (no phone text on the Roku).
  - **Decisions:** D7–D12 in [M12-decisions-log.md](M12-decisions-log.md).
    - The title index (kept until the next guide load; step 22's memory alerts drop it).
    - Teams from TeamsTask.
    - All results after the 0.3 s debounce.
    - Search only from the guide's Search row.
    - The frame's layout with MMTVL's wording and 6 rows.
    - Programme titles also match without accents, a superset of MMTVL's ASCII `LIKE`.
  - **QA fixes:**
    - Serials keep increasing across Search sessions, so a late answer from a closed session is dropped.
    - A failed part clears "Searching…".
    - The 8- and 40-result caps are tested.
    - The Search-row round trip is tested along the scene's path.
    - The scene loads no search code (a plain counter), so the fold tables stay off the render thread.
  - **Accepted:** the index build can't be cancelled, so a newer query waits for it. `programmeDetails` runs up to 40 linear scans on the render thread per answer (estimated at tens of ms on a stick; a binary search if a device shows lag).
  - **Device checks (step 23):**
    - **Typing:** results update while typing on the stick with no dropped key presses (the done-when).
    - **Keyboard keys:** which keys `DynamicMiniKeyboard` passes through (Right at its edge, Back, Play), and its cursor after Play deletes.
    - **Back:** from the keyboard it returns to the Search row; from the results, to the keyboard.
    - **Idle return** closes Search.
    - **OK:** on a channel or a programme on now, it plays; on a later programme, it shows that row and start in the guide (TimeGrid `jumpToTime`, if present); on a team, it toggles the team and its check mark, and the change survives a relaunch.
    - **Look:** the palette (`RSGPalette`) and layout at 1080p and 720p.
    - **First search after a guide load:** "Searching…" while the index builds, and the DEBUG "Indexed …" and "Found …" lines (time and memory on a Low Roku).
- **2026-11-22, step 20 (built; qa-deep PASS with minors, all fixed).**
  - **New files:**
    - `EPGSuggester.bs`: the `rank` port, with a double-precision `ln`, because BrightScript's `Log` is single precision and would change ties.
    - `MatchGuide.bs`: options, menu, `overridesAfter`, labels.
    - `MatchGuideTask`: ranks off the render thread; the newest request wins.
    - `suggestions.golden.json`: 42 cases, written by Swift.
  - **Changes:** a "Match Guide…" row in the channel menu, showing the guide label, else "None". `GuideRuns` gets `rematch` and `cachedOnly`. `GuideFetch.fetchStep` and `matchData`. `GuideTask` gets `cachedOnly`. The Channels footer is back to "favorite, hide or match".
  - **Counts:** `test:local` 624 passed; MMTVL full suite 2096; release 114 files.
  - **Test mapping:** EPGSuggesterTests 5/5. IPTVLibraryTests' and LiveTVModelTests' Match Guide cases are carried, except the scene-level ones (Back to the channel menu, a newer open, the idle cancel, closing both menus), which are step 23 device checks.
  - **Decisions:** D13–D20 in [M12-decisions-log.md](M12-decisions-log.md):
    - the rematch is a guide run that downloads nothing;
    - `matchData` is split from `guideData`;
    - MatchGuideTask and MMTVL's 30 suggestions;
    - the channel menu's look, with MMTVL's wording;
    - a refused save keeps the menu open, with at most 500 matches;
    - the answers to the implementer's questions;
    - the scene keeps `Unicode.bs`, and SearchView's imports go to step 22;
    - "Selected" instead of " · Selected".
  - **QA fixes:**
    - The per-guide fetch decision is pure and tested (`fetchStep`).
    - A tie-break case where guide order and id order disagree is now in the Swift golden.
    - A failed or abandoned rematch sets `rematch` again and is retried after the 1-hour wait.
  - **Accepted:** Swift sums weights in Set order and the Roku in sorted order, so a golden tie could in theory differ by one ulp; it was never seen in 21 Swift runs. A guide that falls due during a rematch is fetched at the next 15-minute tick.
  - **For step 21:** antenna channels need the antenna guide's suggestions first (MMTVL M7j L12), which is a MatchGuideTask change.
  - **Device checks (step 23):**
    - The done-when: a match on an unmatched channel shows after the rematch and survives a relaunch. No download line appears during a rematch.
    - Back and `*` return to the channel menu, focused on Match Guide…. The idle return closes it, including while it loads. A newer open, or Choose Teams, opened while it loads drops the old answer.
    - The rematch's time on a stick with US2 ("Read N guide(s) in X s").
    - The wide panel at 1080p and 720p, with right-aligned values, the `·` and `…` glyphs and the wrapped note. The low-space note on a nearly full registry.
    - `LCase` on non-ASCII on the device. Doubles kept in arrays and AAs (run EPGSuggester's golden on the device).
    - `*` in the player → Match Guide.

- **2026-11-22, step 21 (built by the implementer; QA and the security review to follow).** Every path is built, gated (U1): the switches are `roku/source/lib/AntennaConfig.bs`, decisions D21–D34 in [M12-decisions-log.md](M12-decisions-log.md).
  - **New:** `HDHomeRun.bs` (the packet, the discovery and acceptance rules, the tuner's JSON, the diagnosis; the network is an injected io), `AntennaLineup.bs`, `AntennaGuide.bs` (URL, schedule, matching, both guide formats, the DeviceAuth read), `AntennaConfig.bs`, `components/tasks/AntennaTask.*` (the real io: `roDataGramSocket`, `roUrlTransfer`), and four `test:local` suites.
  - **Changed:** GuidePipeline reads the antenna guide's file for antenna channels only (`antenna` request; GuideTask never fetches it); `GuideFetch.antennaRow`, `matchData.antennaIndex`; `EPGSuggester.suggestions` (the antenna guide first for antenna channels, MatchGuideTask); `MatchGuide.withAntennaLabel` ("HDHomeRun"); the player plays antenna streams per D24/D25 and reports the error's numbers; the scene merges the antenna's channels after the playlist's, waits for both at launch, diagnoses failures and retries once; Settings → Antenna, the Antenna row, the Device MPEG-2 line; `settings.antennaAddress` (Roku-only).
  - **Counts:** `test:local` 698 passed (624 + 74) as first built; 710 after the QA fixes below; release 120 files. MMTVLTests unchanged (no golden: D34).
  - **Test mapping:** AntennaLineupTests 19/19 (channelSourceHidesTheDeviceID as "no channel field holds a DeviceID"); AntennaDiagnosisTests 8/8; AntennaGuideTests 11/11 (sourceIDHasNoToken as "the guide's files hold no token"); HDHomeRunPacketTests and HDHomeRunDiscoveryTests where a Roku applies (no interfaces, netmasks or Mac addresses: the Roku's /24s); SettingsModelTests' antenna page cases without the scan and Channels page; HDHomeRunScanTests and HDHomeRunAPITests' scan cases don't apply (no scan on the Roku).
  - **Device checks (step 4/23):** probe f (broadcast send from a Roku; `hdhomerun.local` resolving; `GetTargetIpAddress` for D23); probe b (raw TS with each `streamFormat`, MPEG-2 decode, 1080i); what a Video error's texts hold for a tuner's 503/404/805; a zap between two antenna channels on a 2-tuner HDHR4 (the old stream must close first); the SiliconDust XMLTV's size and speed on a stick, and whether it comes gzip-encoded without `Accept-Encoding`; the JSON guide's shape and window (if D27 flips); `roByteArray.GetCRC32` matching zlib's on the device (brs-node does); `FromAsciiString` writing UTF-8; Settings → Antenna's look at 1080p and 720p.
  - **QA (qa-deep FAIL, 4 majors) and security review (lows only): fixes.**
    1. The retry replays the channel in place and never changes the screen (`PlayerSession.retryAction`, D35).
    2. A new stream URL or tuner count now reaches the channels. The task gives `matchKey` and `payloadKey` (`AntennaLineup.setKeys`); `Lineup.antennaChange` merges on the payload and rematches only on ids and names (D37).
    3. The lineup answers first (`lineupResult`, `AntennaLineup.refreshRun`). The launch waits only for it (and its merge), not for SiliconDust's download (D36).
    4. The merge is off the render thread. PlaylistTask merges the antenna part on every load, and a new antenna part runs a merge-only PlaylistTask (`Lineup.mergeParts` and `playlistPart`). The scene only assigns, except antenna-only lists after the playlist is removed (D37).
    5. `errorNumbers`:
       - skips "/1.x" after "http" and reads statuses after "status", "code" and "returned";
       - reads 801/805–807 only after "hdhomerun" or "error";
       - never reads a number in a URL or after "/" or "v".
       The test now has the failing strings as cases.
    6. A tuner whose lineup can't be read keeps its channels (`withKept`, D41).
    7. Find Tuners' line and "Searching…" (D42).
    8. Busy-time requests wait and run after (`m.antennaPending`). A guide download that can't start waits for the guide run (`m.antennaGuidePending`, D38).
    9. The player's content and refusal for each switch value are in `PlayerSession.antennaContent`, tested both ways; a gzip-on fetch case was added.
    10. `codecUnknown` and the MPEG-2 hint (D40; D26 updated).
    11. D31 corrected to about 3.5 s; the 2 s name probe kept (D39).
  - **Security lows:**
    - **L-1 (fixed):** an AntennaTask given up on keeps the guide file gated while alive (`m.abandonedAntennaTask`, `GuideRuns.antennaBusy` and `antennaMayDownload`, tested). The download's watchdog is 300 s for the XMLTV and 600 s for the JSON guide (D38).
    - **L-2 (fixed):** `refreshRun` always ends with `io.cleanup()` (the GET body and the guide's `.part`), crash or not (tested with a fake that throws after writing); a diagnosis deletes its own body.
    - **L-3 (fixed):** the guide screen gets `SettingsStore.guideSettings` (`{ channelLogos }` only), tested to carry no `antennaAddress`. The other node fields (typed, the diagnose URL, the channels' URLs) stay for step 24's L-3.
    - **L-4 (recorded; partly done):** `fetch` clears the DeviceAuth list once the URL holds them. The tokened URL still lives in a local and the roUrlTransfer for the download's length, so a crash backtrace on port 8085 can show it (dev mode only, as step 9's L-7).
    - **L-5 (recorded; must fix before D27 flips to "json"):** the JSON guide holds every page in memory and has no total cap.
  - **Device checks added:** timing a merge-only PlaylistTask with a 10,000-channel playlist and antenna channels on a stick (D37); the lineup answer's time at launch with no tuner (about 3.5 s, D39); a retry under the guide's preview and under Settings (D35).
  - **QA round 2 (qa-deep FAIL, 1 major; the other fixes held).**
    1. **(major)** `onPlaylistWatchdog`'s full-load branch now calls `afterPlaylistTask()`, so a merge that waited during a slow load starts, and the launch opens after it. `stopPlaylistTask` clears `mergePending` (`Lineup.afterStop`), so an import with no playlist URL doesn't wait forever. The decisions are `Lineup.afterTask`, `launchWaits` and `afterStop`, tested ("the watchdog with a merge pending: a merge starts"; "a stop clears pending"). `applyAntennaOnly` marks the antenna part merged.
    2. The retry waits for a lineup answer from the run its diagnosis asked for, or a later one (`{ id, minSerial }`, D43, tested).
    3. A retry under Settings waits for `closeSettings` (D44, tested).
    4. `ioCleanup` deletes the guide's `.part` only when this run downloaded (`refreshRun` passes it; the cleanup test checks both).
    5. `onAntennaLineup` and `onAntennaResult` ignore answers whose serial isn't the tracked run's.
    6. `onAbandonedGuideTaskState` calls `antennaGuideMayGo()`.
    7. An import that turns the antenna on resets `m.antennaAnswered` while the launch is pending, so the import's launch waits for the antenna's lineup.
    - **Accepted, no change:** the remaining O(n) field copies (D37's cons, with the 10k device check), and "Searching…" during a queued Find (D42).
    - **Orchestrator's review:** the merge watchdog's branch also cleared no `mergePending` that was set while the merge ran, so the launch could still wait. It now clears it (the revision −1 brings the merge back at the next task's end; restarting it there could loop every watchdog period).
    - `test:local`: 713 passed. Security review (step 21's done-when): no findings above low; L-1, L-2 and L-3 fixed, L-4 and L-5 recorded (L-5 must be fixed before D27 flips to "json").
