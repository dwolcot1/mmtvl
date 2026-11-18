# M12 — Roku Live TV

| | |
|---|---|
| Status | In progress |
| Depends on | M4, M6b, M7j, M7l, M7m, M7n (the Live TV behaviour it clones) |
| Master plan decisions used | D9, D23, D26, D48, D49, D52; new D54, D55, D56 |
| Planned | 2026-11-18 |

## Next session starts here

- **Phase 0 (PR #1)** and **phase 1 (PR #2, stacked on PR #1)** are done off-device. Steps 1, 4 and every device check wait for the remote tester's Roku. The probe build is `cd roku && npm run build` → `roku/out/mmtvl-live-tv.zip`. **Ask the user before sending it.**
- **Next: Phase 2 (UI).** Step 10 is `[designer]` in the user's pen.dev, and the user picks a frame for each screen before steps 11–13. Phase 3's step 14 (migration) needs no device until step 15.
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
  - **Player:** Up/Down zap (direction from `channelUpMovesUpList`); OK toggles the banner (or retries on the error panel); `*` opens the channel menu; **Replay** goes to the previous channel; Play/Pause pauses (Roku pause buffer); Rewind/Fast Forward skip 10 s within the live window (clamped 30 s from the edge); Back hides the overlays, else opens the guide.
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
  - **Low** (≤ 512 MB limit class or a 720p UI): a 24 h guide window, logos off by default, no inflate for guides over 2 MB compressed, and the Antenna MPEG-2 channels hidden unless `mpeg2`.
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

- [ ] **10. The Roku look** `[designer]`
  - In the user's pen.dev, design the player banner (channel, number, logo, now/next with times and progress), the error panel, the guide (group column plus TimeGrid in its styleable fields), the channel menu, Search, Choose Teams, Settings rows, the Import confirm screen, and Settings → Device.
  - Base them on MMTVL's Live TV and `DesignSystem/Theme.swift` tokens. SceneGraph has no blur, so glass is 9-patch translucent panels with a rim; the banner role (D46) is a darker, more opaque panel.
  - Make a 720p check of type sizes (FHD scaled down).
  - Then write `roku/components/theme/Theme.bs` (colors, fonts, sizes) and the 9-patch images.
  - **The user picks** before steps 11–13 build the screens.
  - Done when: the user has approved a frame for each screen, and `Theme.bs` builds.
- [ ] **11. Player** `[implementer]`, files: `roku/components/player/**`, `MainScene`
  - L4 player keys.
  - The banner shows on a channel change and on OK, and hides after 5 s.
  - Paused overlays fade after 15 s (D51).
  - The error panel ("Can't play this channel", OK retries) appears on a `Video` error or a stall over 15 s.
  - Keep the last channel and recents (10) in `state`.
  - At launch, open the last channel full screen if there is one, else the guide.
  - Done when: `PlayerKeyTests` (a key-to-action table: zap direction, Replay, Back states) pass, and with a device, zapping and Back show as L4 says.
- [ ] **12. Guide** `[implementer]`, files: `roku/components/guide/**`
  - L3 and L4 guide keys.
  - TimeGrid fed lazily, per visible channel, from the GuideTask results; "No guide" rows for unmatched channels.
  - Channel logos through `LogoTask` (cachefs, off on low devices).
  - The channel menu: Watch, Add/Remove Favorites, Move Up/Down (Favorites), Hide Channel, Match Guide (step 20).
  - Remember `lastGroup`.
  - The guide returns to the playing channel after 3 minutes without a press (D51).
  - Done when: `GuideKeyTests` (the GuideModelTests cases that apply: group looping, Search above the groups, Back states, paging by 6) pass, and with a device, the guide opens in under 2 s with the guide loaded.
- [ ] **13. Settings** `[implementer]`, files: `roku/components/settings/**`
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

- [ ] **14. Export script and import** `[implementer][security]`, files: `scripts/roku-export-settings.py`, `scripts/test_roku_export_settings.py`, `roku/components/tasks/ImportTask.*`, `roku/components/import/**`, `roku/source/main.bs`
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

- [ ] **16. Teams data** `[implementer]`, files: `roku/data/pro-teams.json`, `roku/bsconfig.json` (copy `../MMTVL/IPTV/Teams/college-teams.json` into the package at build), `MMTVLTests/RokuParityTests.swift`
  - A Swift test checks that `TeamCatalog`'s pro teams serialize exactly to `roku/data/pro-teams.json` (id, league, name, nickname, aliases, abbreviations), so the golden file can't drift.
  - The college catalog is loaded lazily in a Task (382 KB).
  - Done when: the parity test passes, and the package contains both files (`unzip -l out/*.zip`).
- [ ] **17. TeamMatcher port** `[implementer]`, files: `roku/source/lib/TeamMatcher.bs`, `TeamCatalog.bs`, `roku/tests/fixtures/teams.golden.json`, tests
  - Game entries ("Away @ Home", not in "…Replay…" groups), programme matching (pro full name, nickname + league word; college "A at B" exact school, the description's first sentence by linear scan, aliases, nickname appended, apostrophes dropped), the Match Initials and Match Nicknames Alone switches, and `upcomingGames`.
  - Fixtures carry over the TeamMatcherTests (42) and MyTeamsTests (14) cases. The Swift side checks `teams.golden.json` too (in `RokuParityTests`).
  - Done when: both sides pass the golden file, and on a device, matching 100 channels' now-programmes takes under 500 ms on the stick (console timing).
- [ ] **18. My Teams** `[implementer]`, files: `roku/components/teams/**`, `Lineup.bs`, guide
  - The My Teams group: Choose Teams… (leagues → conferences → teams, as M7l), live games, up to 30 upcoming games in 3 days (OK tunes), live team games on top of Favorites.
  - Recomputed after playlist and guide loads, after a team is picked, and every 5 min.
  - The channel menu's Add/Remove … to My Teams for pro entries.
  - Settings → My Teams: the picked teams and both Matching switches.
  - Done when: `MyTeamsLineupTests` pass, and on a device, picking a team that's playing shows its game in My Teams and atop Favorites.
- [ ] **19. Search** `[implementer]`, files: `roku/components/search/**`
  - A Search row above the groups (as MMTVL).
  - A `DynamicMiniKeyboard`, results from 2 characters: 8 channels (folded substring), 12 teams (MMTVL's ranking; OK adds or removes the team and keeps search open), 40 programmes in the next 24 h (every word in the title).
  - Debounced 300 ms in a Task.
  - Done when: `SearchTests` mirror LiveSearchTests (17), and on a device, results update while typing without dropping key presses on the stick.
- [ ] **20. Match Guide** `[implementer]`, files: `roku/source/lib/EPGSuggester.bs`, `roku/components/guide/MatchGuide.*`
  - Channel menu → Match Guide: Automatic, No Guide, then ranked suggestions (an `EPGSuggester.rank` port over the channel names collected in pass 1).
  - A choice writes `overrides` (keyed by the channel name; antenna channels by id) and re-runs matching without downloading.
  - Done when: `EPGSuggesterTests` (5) pass, and on a device a match survives a relaunch.

### Phase 5 — antenna (as decided in step 4)

- [ ] **21. Antenna** `[implementer][security]`, files: `roku/components/tasks/AntennaTask.*`, `roku/source/lib/{HDHomeRun,AntennaLineup,AntennaGuide}.bs`, Settings → Antenna, tests
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
