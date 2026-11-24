# M15 — Software updates, Restart, Power-off goes home

| | |
|---|---|
| Status | In progress |
| Depends on | MR (Developer ID, notarized zips on GitHub Releases), M7h (Power, D45), M7m (still screens, screen saver, D51) |
| Master plan decisions used | D20, D33, D34, D35, D36, D45, D51, D57; new D58 (amended here), D45 amended |
| Planned | 2026-11-23 |

## Next session starts here

- **In progress on branch `m15-software-updates`** (from 2026-11-23). Step 1 done (`945a77a`). Next: step 2 (Power-off goes home), then step 3 (Sparkle); step 4 needs the user at this Mac (EdDSA keys) before step 5.
- Human checks gathered so far (on this Mac, `-windowed YES`): Settings → System → Restart Mac mini sits between Relaunch and Exit, its band says "Restarts the Mac mini. Asks first.", and its page shows Cancel first (**press only Back there**). Neither the implementer nor QA drove the running app to that page.
- Read: this plan's *Design*, then the files each step names. Build: `/build-plan docs/plans/M15-software-updates.md`.
- The TV session (step 14) needs two notarized builds (A and B, step 13); both releases need the user's yes.

## Goal

MMTVL keeps itself up to date from its GitHub Releases. When a newer version is out, the home screen shows **"Update Available: 1.4.0"** under the clock. **Settings → System → Software Update** shows the installed and available versions, checks on demand, and installs: MMTVL quits, the new version replaces it, and it opens again on its own. Users choose **Automatic Updates: Off** (the default: only the notice), **When Idle** (download in the background, install after Power turned the TV off or while the screen saver runs) or **At Night** (install around 4 a.m. if nothing is in use). Update checks are on by default and can be turned off. Every update is checked twice before it's installed: Sparkle's EdDSA signature with the maintainer's key, and the Developer ID signature of the new app. **Settings → System → Restart Mac mini** restarts the Mac after a confirm page. And **pressing Power to turn off** stops whatever MMTVL is playing and shows the home screen, so nothing plays to a dark TV and an idle install can start.

The user's words (2026-11-23): "can we build a built in updater for when a new version is available on github"; "notification in MMTVL home screen that an update is available, settings can update manually and install/update. Automatic updates can be enabled by end users"; "include a reboot macOS option under settings -> system"; and, on the idle rule, "when power is pressed, anything playing should stop and return to home".

## Out of scope

- **Delta updates** (Sparkle's BinaryDelta). One full zip per release (L9).
- **Release notes on the TV.** Settings shows versions only; the notes stay on the GitHub release page (L10).
- **Updates in Debug builds or `-windowed` mode.** The updater is off there (L4).
- **Stopping playback in other apps on Power-off.** MMTVL comes forward like Home (D18: the app keeps running); whether Plex HTPC keeps playing behind it is checked on the TV (step 14 B) and handled later if it does.
- **The Roku app.** It has its own release line (D57) and no updater.
- **Signed `.dmg`, Homebrew, Mac App Store.** D33 stands: a zip on GitHub Releases.
- **CI.** Releases stay on the dev Mac (MR L5).

## Research & findings

### Sparkle 2 (primary sources, read at tag `2.10.1`)

Researched 2026-11-23 from the Sparkle source at `2.10.1` (`gh api repos/sparkle-project/Sparkle/contents/<path>?ref=2.10.1`), the SPM binary zip (its SHA-256 matches `Package.swift`'s checksum), and the docs site's source (`sparkle-project/sparkle-project.github.io`, `documentation/*/index.md`). Paths below are Sparkle-relative.

**Release and package**
- 2.10.1 is Latest (2026-10-25); 2.11.0-beta.1 (2026-11-17) only adds a feed bundle-identifier check, mainly for pkg updates.
- SPM URL `https://github.com/sparkle-project/Sparkle`, product `Sparkle` (`Package.swift:15`), a `.binaryTarget` XCFramework (`macos-arm64_x86_64`).
- Minimum macOS 12.0 (`Package.swift:12`; raised in 2.10.0).

**What's in `Sparkle.framework/Versions/B`:** the dylib, `Autoupdate` (the installer), `Updater.app` (the progress agent, `LSUIElement`), `XPCServices/Installer.xpc` and `XPCServices/Downloader.xpc`, plus `bin/` tools in the package.
- A non-sandboxed app needs only the framework, Autoupdate and Updater.app.
- The XPC services are used only with `SUEnableInstallerLauncherService` / `SUEnableDownloaderService` = YES, which the docs say not to set in a non-sandboxed app (docs/customization).
- Removing the XPCs is optional, "to save space" (docs/index). `startUpdater` fails only if an *enabled* service is missing (`SPUUpdater.m:232-265`).

**Signing**
- The shipped helpers are ad hoc signed with the hardened runtime.
- `xcodebuild archive` + `-exportArchive` (Developer ID) re-signs them with the hardened runtime and strips `get-task-allow`. docs/index: "Using Xcode's Archive Organizer will ensure Sparkle's helper tools are code signed properly … `xcodebuild archive` and `xcodebuild -exportArchive`"; docs/sandboxing:65-73.
- **Never `--deep` when signing** (docs/sandboxing:92-94). `codesign --verify --deep` is fine.

**Entitlements in the shipped binaries**
- `Autoupdate` carries `com.apple.application-identifier = org.sparkle-project.Sparkle.Autoupdate`. The other three carry none.
- **Unverified:** whether Xcode's export keeps that entitlement. Step 5 inspects the exported app: `codesign -d --entitlements - …/Sparkle.framework/Versions/B/Autoupdate`.

**Tools**
- Location: `<derived data>/SourcePackages/artifacts/sparkle/Sparkle/bin/` (`generate_keys`, `sign_update`, `generate_appcast`, `BinaryDelta`; docs/index:20). **Unverified** for this repo's `-derivedDataPath build` layout until step 3 resolves the package; check with `ls build/SourcePackages/artifacts/sparkle/Sparkle/bin`.
- `generate_keys` (`generate_keys/main.swift`):
  - It stores the private key as a **login Keychain** generic password: service `https://sparkle-project.org`, account `ed25519`.
  - `-p` prints the public key; `-x <file>` exports the private seed; `-f <file>` imports it.
  - A lost key can be rotated only while the Developer ID certificate stays the same: change one of the two, never both (docs/index:111,127-131).
- `sign_update <zip>` prints `sparkle:edSignature="…" length="…"` (`sign_update/main.swift:287`).
  - `--verify <file> <sig>` checks a signature.
  - Run on an `.xml` feed, it signs the feed in place by appending a `<!-- sparkle-signatures: … -->` comment (`common_cli/Signing.swift:88`).

**Info.plist keys** (docs/customization)
- General: `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` (set: no permission prompt), `SUAutomaticallyUpdate` (default NO), `SUAllowsAutomaticUpdates`, `SUScheduledCheckInterval` (default 86400, minimum 1 h).
- Security: `SUVerifyUpdateBeforeExtraction` (2.7.3+) and `SURequireSignedFeed` (2.9+, needs the former; `SPUUpdater.m:368-380`).
- Which keys can come from elsewhere:
  - **The public key comes only from Info.plist** (`SUHost.m:191-194`); there's no API for it.
  - `SUFeedURL` is read from **user defaults first, then Info.plist** (`SPUUpdater.m:1155-1172`), unless the delegate's `feedURLString(for:)` answers. Step 14 uses that user-defaults override to point only the mini at a test feed.
  - `SUAllowsAutomaticUpdates`, `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` are Info.plist only.
- Setting order: `allowsAutomaticUpdates` equals `automaticallyChecksForUpdates` unless `SUAllowsAutomaticUpdates` is set, and the `automaticallyDownloadsUpdates` setter is ignored while it's false (`SPUUpdaterSettings.m:314-334`). We set `SUAllowsAutomaticUpdates = YES`, and still set checks before downloads.

**No `INFOPLIST_KEY_SU…`**
- With `GENERATE_INFOPLIST_FILE = YES`, Xcode's build service copies only an allow-list of `INFOPLIST_KEY_*` names, and it has no `SU*` keys (swift-build `Sources/SWBTaskExecution/TaskActions/InfoPlistProcessorTaskAction.swift:741-809`; unknown names return nil at :717).
- The supported route is `INFOPLIST_FILE`. Apple's build settings reference: "The build system merges the values you specify in this file with other values it generates … When `GENERATE_INFOPLIST_FILE` is enabled, the build system also includes content from build settings in the merge process" (developer.apple.com/documentation/xcode/build-settings-reference, *Info.plist File*).
- **Unverified:** a plist inside the synchronized `MMTVL/` folder would also be copied as a resource ("Multiple commands produce …"). So it goes outside: `Config/Updater-Info.plist` (L2).

**SPUUpdater** (`SPUUpdater.h`, main actor)
- `init(hostBundle:applicationBundle:userDriver:delegate:)`; **the delegate is held weakly**. `start() throws`.
- `checkForUpdates()` is user-initiated and **does nothing while `sessionInProgress`** (`SPUUpdater.m:712-715`).
- `checkForUpdateInformation()` is a probe with no UI.
- Also: `automaticallyChecksForUpdates`, `automaticallyDownloadsUpdates`, `updateCheckInterval`, `lastUpdateCheckDate`, `resetUpdateCycle()`, `userAgentString`.

**SPUUserDriver** (`SPUUserDriver.h`): `@MainActor`, with 16 required methods:
- `show(_:) async -> SUUpdatePermissionResponse`
- `showUserInitiatedUpdateCheck(cancellation:)`
- `showUpdateFound(with:state:) async -> SPUUserUpdateChoice` (`.install` / `.dismiss` / `.skip`; the state's stage is `.notDownloaded` / `.downloaded` / `.installing`, and it has `userInitiated`)
- `showUpdateReleaseNotes(with:)`, `showUpdateReleaseNotesFailedToDownloadWithError(_:)`
- `showUpdateNotFoundWithError(_:) async`, `showUpdaterError(_:) async`
- `showDownloadInitiated(cancellation:)`, `showDownloadDidReceiveExpectedContentLength(_:)`, `showDownloadDidReceiveData(ofLength:)`
- `showDownloadDidStartExtractingUpdate()`, `showExtractionReceivedProgress(_:)`
- `showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice`
- `showInstallingUpdate(withApplicationTerminated:retryTerminatingApplication:)`
- `showUpdateInstalledAndRelaunched(_:) async`, `dismissUpdateInstallation()`

`showUpdateInFocus()` is optional (2.8+). Don't implement the deprecated ones (`:290-300`).

**The silent path, used by When Idle and At Night** (source-traced)
1. With `automaticallyDownloadsUpdates` on, a scheduled check uses `SPUAutomaticUpdateDriver`, which **never calls the user driver** (`SPUUpdater.m:620-640`).
2. It downloads, then the installer (launchd user job `dev.mmtvl.launcher-sparkle-updater`, `SUInstallerLauncher.m:259-278`) extracts, validates and prepares the swap.
3. It then calls the delegate's `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:) -> Bool` (`SPUAutomaticUpdateDriver.m:104-129`).
   - **YES** "stalls the current update cycle", and the app may call the block later to "install the update and relaunch the application without any UI interaction" (`SPUUpdaterDelegate.h:425-437`). The block may be called again if termination is cancelled.
   - "In either case Sparkle will always attempt to install the update when the app terminates."
4. Calling the block runs `updaterShouldRelaunchApplication` (NO aborts the whole install), `shouldPostponeRelaunchForUpdate`, `willInstallUpdate`, then `updaterWillRelaunchApplication` (`SPUInstallerDriver.m:503-534`; `SPUCoreBasedUpdateDriver.m:307-339`).
5. **While the block is held, `sessionInProgress` stays true**: `checkForUpdates()` is a no-op, and no newer feed is read until the relaunch.
6. Critical updates, information-only items and failed feed signatures fall back to the user driver (`SPUAutomaticUpdateDriver.m:81-97,146-153`). Installs that need authorization get `AuthorizeLater` and come back through the user driver (`SUInstallerLauncher.m:469-473`).

**How Sparkle quits the app**
- Updater.app calls `NSRunningApplication.terminate()`, an Apple quit event, so **`applicationShouldTerminate` is consulted** (`InstallerProgressAppController.m:375-385`).
- If it returns `.terminateCancel` (the kiosk lock's PIN prompt), Sparkle just waits; calling the block again re-sends the quit (`Autoupdate/AppInstaller.m:654-680`).
- After the swap, Autoupdate relaunches with `NSWorkspace.open(bundleURL)` 0.3 s later, **with no launch arguments** (`InstallerProgressAppController.m:387-420`), so `-windowed` would be lost (L4).
- **On the UI path, Updater.app may show its own progress window** if the install takes over 0.7 s after the quit (`AppInstaller.m:46,763-786`). The silent block path shows none (risk; checked on the TV, step 14 C).

**Verification** (`SUUpdateValidator.m:304-376`): at least one of these must pass:
- EdDSA over the archive **with the old app's key**;
- the new bundle satisfying the **old bundle's designated requirement** (`Autoupdate/SUCodeSigningVerifier.m:26-77`).

Also:
- Removing the key or dropping code signing is always rejected.
- **Downgrades are refused** (by `CFBundleVersion`, `SUPlainInstaller.m:323-345`).
- Quarantine is stripped from the new bundle, and owner/group are copied from the old one.
- The swap is atomic (`renamex_np(RENAME_SWAP)`), which keeps the path but not the inode. The swap and Gatekeeper pre-warm run only when Autoupdate's Team ID equals the update's (`SUPlainInstaller.m:346-376`); export signing gives both our team.

**Not writable:** if the bundle or its folder isn't writable by the user, an install from the user driver asks for an **admin password** through the system dialog (`SUInstallerLauncher.m:339-374`), which a remote can't answer. The silent path never asks; it defers to the UI path. Q35.

**Translocated or read-only copies** abort the check quietly (`SPUBasicUpdateDriver.m:71-83`).

**Zip advice:** only the app in the zip, made with `ditto -c -k --sequesterRsrc --keepParent` (docs/publishing).

**Appcast item** (docs/publishing)
- `sparkle:version` = the new `CFBundleVersion` (our build number), and `sparkle:shortVersionString`.
- `sparkle:minimumSystemVersion` `26.0.0`, and `pubDate`.
- `<enclosure url length type="application/octet-stream" sparkle:edSignature>`.
- Optional: `sparkle:criticalUpdate`, `sparkle:channel`.
- `SUStandardVersionComparator` compares `CFBundleVersion` component-wise.

**Redirects:** Sparkle's downloader follows them (`Downloader/SPUDownloader.m:65-86` checks only the first URL's scheme).

**Any termination installs a staged update.** Autoupdate waits for the host to exit. **Unverified:** for SIGTERM/SIGKILL; it follows from the source and is checked in step 14 G.
- That includes `deploy-mm.sh`'s SIGTERM. A build staged before a deploy could then replace the deployed build: the downgrade check compares against the version that was installed when staging began.
- Step 9 boots out Sparkle's launchd jobs before the deploy stops MMTVL.

**User defaults:** Sparkle keeps its own `SU*` keys in MMTVL's user defaults (`dev.mmtvl.launcher`), e.g. `SULastCheckTime`, `SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`.

**License:** `LICENSE` is MIT (Andy Matuschak and others, 2006–2017), with an *External licenses* section covering:
- bsdiff 4.3 (BSD 2-clause);
- sais-lite (MIT);
- orlp/ed25519 (zlib);
- `SUSignatureVerifier.m` (BSD 2-clause).

### GitHub Releases (verified 2026-11-23)

- `curl -sI https://github.com/dwolcot1/mmtvl/releases/latest/download/MMTVL-1.3.0-build42.zip` answered `302` to `…/releases/download/v1.3.1/MMTVL-1.3.0-build42.zip`. So `releases/latest/download/<asset>` resolves to the release marked **Latest**: v1.3.1 (`gh release view -R dwolcot1/mmtvl` → `v1.3.1`, asset `MMTVL-1.3.1-build43.zip`).
- Roku nightlies are prereleases published with `--latest=false` (D57, `roku-v0.1-build2…6`), so Latest stays MMTVL's.
- A draft release isn't Latest until it's published. The checklist publishes only after a check on the mini, so no user is offered a release before that check.
- **Feed URL:** `https://github.com/dwolcot1/mmtvl/releases/latest/download/appcast.xml`. Today it 404s (v1.3.1 has no appcast); Sparkle reports an error, which MMTVL shows as "Couldn't Check" (L12).
- v1.3.1's notes have `# MMTVL 1.3.1`, `## Install`, the SHA-256, `## What's in this release` and `## Upgrading`. 1.3.x users have no updater: 1.4.0 is installed by hand once (README and notes, step 11).

### The app today (file:line, read 2026-11-23)

**Restart already exists in the power menu**
- `Launcher/PowerMenu.swift:5` `PowerMenuAction.restartMac`, `:8` `needsPIN`, `:37` the title "Restart Mac mini".
- `AVControl/PowerController.swift:245` `restartMac()` logs "Power menu: Restart Mac mini" and toasts "Couldn't Restart the Mac mini" on failure (`:249`). The effect is `SystemPower.sendToLoginWindow(AEEventID(kAERestart), name: "restart")` (`:428`, `:490-508`; QA1134, sent off the main actor, logs "Power: asked loginwindow to restart").
- AppDelegate calls it at `App/AppDelegate.swift:714` (`performPowerAction`). The power menu asks for the PIN (`Launcher/AppRouter.swift:1062-1071`, `PIN/PINFlow.swift:10`).
- A logout/restart sets `allowsTermination = true` through `observePowerOff` (`AppDelegate.swift:1259`, kiosk only, `:250`), so the kiosk guard doesn't block it.

**Settings model** (`Settings/`)
- `SettingsPage` (`SettingsTypes.swift:3-38`: `system`, `about` at `:21`, `glassStyle` `:31`, `confirmAntennaScan` `:35`).
- `SettingsAction` (`:327-400`: `.push` `:331`, `.relaunch` `:332`, `.pop` `:341`, `.setGlassStyle` `:383`, `.startAntennaScan` `:394`).
- `SettingKey` for Bool toggles (`:271-323`).
- `SettingsRow` (`:425-444`): `id`, `title`, `value`, `detail`, `image`, `showsDisclosure`, `isDimmed`, `isLifted`, `needsRelaunch`, `action` (nil = info row), `description`. `SettingsSection` (`:446-451`): `id`, `title`, `rows`, `footer`.
- Pages map to sections in `SettingsModel+Pages.swift:12-65` (`.system` at `:46`) and to titles at `:68-122`.
- `systemSections` (`:250-299`): Permissions, Startup, Appearance (Glass `:285-288`), and the **MMTVL** section (Relaunch `:291`, Exit to Desktop `:293`).
- The root's System description (`:188-189`): "Accessibility access, starting at login, relaunching MMTVL and leaving to the desktop."
- Confirm pages to copy:
  - `confirmAntennaScanSections` (`:755-762`): `confirm.cancel` → `.pop`, `confirm.scan` → `.startAntennaScan`, a footer; title "Scan for Channels?" (`:119`).
  - Its handler (`SettingsModel.swift:475-479`) calls the environment, then `pop()`.
  - Also `confirmRemoveIPTVSections` (`:894-901`) and `confirmPlexSignOutSections` (`:1166-1171`).
- Choice page to copy: `glassStyleSections` (`:1511-1518`; `value: "Selected"` on the current one). Its handler (`SettingsModel.swift:551-559`) copies the settings, sets the field, calls `environment.applySettings(new)`, then pops.
- `SettingsModel` is `@Observable` (`:5`).
  - Snapshots are `private(set) var`s (`:44-78`), refreshed by `refreshStatus()` (`:222`) or `refreshStatus(_ parts: StatusParts)` (`:263`; `StatusParts` `:235-254`), only while showing.
  - The app pushes changes, e.g. `iptvLibrary.onStatusChange = { router?.settings.refreshStatus(.iptv) }` (`AppDelegate.swift:193`).
  - `perform(_:)` is at `SettingsModel.swift:384` (`.relaunch` → `environment.relaunch()` `:408-409`); `push` `:905` (on-enter hooks `:913-946`); `pop` `:949`.
- `SettingsEnvironment` (`SettingsEnvironment.swift`) is a struct of closures: `version: AppVersion` (`:7`), `relaunch` (`:19`), `showToast` (`:116`). It's built in `AppDelegate.makeSettingsEnvironment(kiosk:)` (`:1455`; relaunch at `:1471`).
- Settings is behind the PIN when one is set (`AppRouter.swift:1494-1495` → `requestPIN(.openSettings)`).

**AppSettings** (`App/AppSettings.swift`)
- Synthesized `CodingKeys` with a custom `init(from:)` (`:114`): a new key is a property with a default plus one decode line.
- Enum pattern: `glassStyle` (`:80`, decode `:167-168`: `((try? container.decodeIfPresent(String.self, forKey: .glassStyle)) ?? nil).flatMap(GlassStyle.init(rawValue:)) ?? defaults.glassStyle`).
- Changes reach `AppDelegate.applySettings(_:)` (`:1275-1359`), which saves, then diffs old against new (e.g. `:1340`, `:1350`).

**Tests**
- `MMTVLTests/SettingsTestSupport.swift`: `SettingsRecorder` (`:5`) and `makeSettingsModel(…)` (`:119`; version `1.1.0` build `7`), `press`/`open` (`:247-255`).
- `SettingsModelTests.swift`: `systemActions` (`:144`), `glassRowChoosesTheGlassStyle` (`:154`), `SettingsLiveTVTests.confirmPageScanStartsAndPops` (`:1258`).
- `AppSettingsTests.swift`: `emptyObjectDecodesToDefaults` (`:6`), `glassStyleDecodes` (`:398`), `unknownReceiverValuesReadAsDefaults` (`:174`).

**Termination and relaunch**
- `allowsTermination` (`AppDelegate.swift:74`).
- `applicationShouldTerminate` (`:1264-1272`): `guard !allowsTermination, isLockEffective, let router else { return .terminateNow }`, else the PIN quit (`router.requestQuit()`) and `.terminateCancel`.
- `isLockEffective` (`:1181-1187`). Places that set `allowsTermination = true`: `:180` (PIN-checked quit), `:675` (power-menu relaunch), `:1259` (logout/restart), `:1471` (Settings relaunch).
- `App/AppRelauncher.swift:26-43` uses a `/bin/sh` helper that waits for our PID, then `open -n` with the original arguments.

**Startup and timers**
- `applicationDidFinishLaunching` (`:88-271`); `kiosk = !AppEnvironment.windowedMode` (`:113`, `App/AppEnvironment.swift:5`).
- Power is set up at `:245` (`setUpPower`, `:670-700`); the IPTV refresh timer and battery polling at `:261-265`.
- Timers are `Task` loops (`startIPTVRefreshTimer`, `:398-415`), kept as properties and cancelled in `applicationWillTerminate` (`:417-420`).
- System wake: `observeWake` (`:1113`) → `systemDidWake` (`:1160-1177`).

**Idle signals** (there's no single "playing" flag)
- `PowerController.poweredOffByMMTVL` (`AVControl/PowerController.swift:179`, `private(set)`, memory only): set in `runOff` (`:300-326`, `:304`), cleared in `runOn` (`:328-…`, `:330`).
  - `runOff` toasts "Turning Off…", turns the TV and receiver off, `effects.keepMacAwake(true)` and `effects.sleepDisplays()`.
  - Callbacks: `onToast` (`:193`) and `onPowerOn` (`:196`, wired at `AppDelegate.swift:680-682` through `PowerController.powerOnHandler` (`:390-395`) → `goHomeFromAnywhere(reason: "powerOn")`). There is **no `onPowerOff`**.
- Screen saver: `App/ScreenSaver.swift` (`isRunning` `:49`, `startedByMMTVL` `:52`), owned by `AppDelegate.screenSaver` (`:81`). `AppRouter.isScreenSaverRunning` (`:131`).
- `AppRouter.idlePhase` (`:123`, `.awake` / `.dimmed` / `.screenSaver`), `areDisplaysAsleep` (`:153`), `isAppActive` (`:81`), `screen` (`:26`; `Screen` `:15-22`).
- `LiveTVModel.isShowingVideo` (`IPTV/LiveTVModel.swift:716`; excludes paused) and `isPreviewPlaying` (`:253`).
- `ReflectorMonitor.isMirroring` (`Cast/ReflectorMonitor.swift:24`), `windowController.isExitedToDesktop` (`AppDelegate.swift:1186`).

**Going home**
- `goHomeFromAnywhere(reason:)` (`AppDelegate.swift:1101-1110`): ends mirroring, `kioskGuard.homePressed()`, `launcher.homePressed()`, `router?.goHomeToStartTile()`, `windowController?.show(reason:)`.
- `AppRouter.goHome()` (`:1269-1293`) pauses YouTube and calls `liveTV.leave(keepingPreview: livePreviewEnabled)`; the preview keeps playing until `updateLivePreview()` or `screensDidSleep()` (`:413-416` → `stopPreviewUntilInput()`) stops it.
- So today, Power-off with Live TV playing keeps the stream running into sleeping displays.

**Home clock**
- `HomeView.swift:109-118` is a trailing `VStack(spacing: Theme.homeClockStackSpacing)`: clock + battery, then `if let versionLabel { capsule(Text(versionLabel)) }` (`:114`).
- `capsule()` (`:161-168`): `Theme.clockFont`, `Theme.primaryText`, `.glassPanel(in: Capsule())`.
- The label comes from `router.homeVersionLabel` (`AppRouter.swift:69`, passed at `:1706`), set at `AppDelegate.swift:225`, `:1343` from `showVersionOnHome`.

**Other**
- `AppVersion` (`App/AppVersion.swift:5-23`): `version`, `build`, `.current`, `label`; no comparison.
- Toasts: `OverlayToast.shared.show(_:symbol:)` (`DesignSystem/OverlayToast.swift:28`).
- HTTP: Sparkle does its own; MMTVL makes no request for updates.
- Login item: `SMAppService.mainApp` (`App/LoginItem.swift:12-29`) follows the bundle in place; nothing hard-codes `/Applications/MMTVL.app`.

### Release scripts (file:line)

**`scripts/release.sh` (191 lines)**
- Entitlement allowlist `(com.apple.security.automation.apple-events)` at `:31`; the team from `ExportOptions.plist` (`:35`).
- `codesign --verify --deep --strict` (`:110`).
- `check_signature()` (`:114-130`): Developer ID Authority, TeamIdentifier, `runtime` flag. It's run on the app and on `Contents/Frameworks/*.framework` **one level only** (`:133-138`).
- Entitlements are read **from the app only** (`:140-153`).
- Notarize `:155-176`; staple, validate and `spctl` `:178-182`; zip `ditto -c -k --keepParent` `:185-191` (prints the SHA-256).
- Sparkle's helpers would get only the `--deep` verify, with no Authority, runtime or entitlement check per item: step 5.

**Other scripts**
- `scripts/ExportOptions.plist`: `developer-id`, team `H846CY8RB4`, automatic.
- `scripts/test-build.sh:4-6`: a Release build, **Development-signed, not notarized**, zipped to `~/Desktop`.
- `scripts/deploy-mm.sh`: `stop_mmtvl` (`:64-72`) sends SIGTERM; `install_zip` (`:93-105`) runs `ditto -x`, `codesign --verify --deep --strict`, the build check, `rm -rf` + `mv`, then start.

**`project.pbxproj`**
- MPVKit `exactVersion 1.0.0` (`:400-407`), GRDB `upToNextMajor 7.11.1` (`:408-415`).
- Product dependencies `:419-428`, the app's `packageProductDependencies` `:99-102`, the Frameworks phase `:43-51`.
- `GENERATE_INFOPLIST_FILE = YES` (`:273`, `:308`, …); `INFOPLIST_KEY_*` at `:274-279` / `:309-314`. No `INFOPLIST_FILE`, no entitlements file, no `OTHER_CODE_SIGN_FLAGS`.
- `MARKETING_VERSION = 1.3.1`, `CURRENT_PROJECT_VERSION = 44`.

**Licenses**
- `Settings/ThirdPartyLicenses.swift`: `ThirdPartyComponent` (`:5-20`: `id`, `name`, `version`, `license`, `copyright`, `url`, `frameworks`); the comment at `:26-28` says the `.framework`s are empty placeholders; GRDB example `:55-60`.
- `Licenses/THIRD_PARTY_NOTICES.md`: `## How the libraries are included` (`:39`, `:43-44` "empty placeholders"), `## Components` (`:51`), `## License texts` (`:354`).
- `MMTVLTests/ThirdPartyLicensesTests.swift:33-47` lists `Bundle.main.privateFrameworksURL` and needs each framework in exactly one component's `frameworks`. `:56-66` needs each name in the notices.

**Other files**
- `scripts/gitleaks.toml`: default rules plus five custom ones. A committed `SUPublicEDKey` (44 base64 characters) may trip `generic-api-key`: step 5 allowlists that one line.
- README `:29`: "To update, quit MMTVL and replace the app the same way; settings are kept."

### Unverified (and where each is checked)

| What | How | Step |
|---|---|---|
| `INFOPLIST_FILE` outside `MMTVL/` merges with the generated plist, no duplicate-output error | Build; `PlistBuddy -c 'Print SUFeedURL'` and `-c 'Print NSLocalNetworkUsageDescription'` on the built app | 3 |
| The tools' path under `build/SourcePackages/artifacts/sparkle/Sparkle/bin/` | `ls` after resolve | 3 |
| Export signs Autoupdate, Updater.app and the XPCs with Developer ID + runtime, and which entitlements Autoupdate keeps | archive + export to the scratchpad, `codesign -dvv` / `--entitlements -` | 5 |
| An update keeps Accessibility, Keychain access and Launch at Login | TV session | 14 C |
| `/Applications/MMTVL.app` on the mini is owned by the logged-in user (no admin prompt) | `ssh mm "ls -ld /Applications/MMTVL.app"` | 14 (before) |
| Updater.app's progress window on the UI path | Watch the TV during a manual Install | 14 C |
| SIGTERM from `deploy-mm.sh` installs a staged update | Step 14 G with step 9's bootout off, then on | 14 G |
| The launchd domain of Sparkle's jobs (`gui/<uid>` vs `user/<uid>`) | `ssh mm "launchctl print gui/\$(id -u) \| grep sparkle"` while an update is staged | 9, 14 G |
| A relaunch during Power-off leaves the displays asleep | TV session | 14 E |
| Plex HTPC keeps playing behind MMTVL after Power-off | TV session | 14 B |

## Design

### New and changed files

| File | Responsibility |
|---|---|
| `Config/Updater-Info.plist` (new; outside the synchronized `MMTVL/` folder) | Sparkle's keys only. Merged into the generated Info.plist through `INFOPLIST_FILE` (L2). |
| `MMTVL/Updates/AutomaticUpdates.swift` | `nonisolated enum AutomaticUpdates: String, CaseIterable, Codable { case off, whenIdle, atNight }` with `title` and `description`. |
| `MMTVL/Updates/UpdateStatus.swift` | `nonisolated struct AvailableUpdate: Equatable, Sendable { version: String; build: String }`, `nonisolated enum UpdateStatus: Equatable`, the home label and the Settings texts (pure, tested). |
| `MMTVL/Updates/UpdateIdlePolicy.swift` | `nonisolated struct UpdateIdleSnapshot` and `nonisolated enum UpdateIdlePolicy { static func mayInstall(_ mode: AutomaticUpdates, _ s: UpdateIdleSnapshot) -> Bool }` (pure, tested). |
| `MMTVL/Updates/UpdaterEngine.swift` | `protocol UpdaterEngine: AnyObject` (what `SoftwareUpdater` needs from Sparkle) and `final class SparkleEngine: UpdaterEngine` wrapping `SPUUpdater`. One of only two files that `import Sparkle`. |
| `MMTVL/Updates/SparkleBridge.swift` | `final class SparkleBridge: NSObject, SPUUserDriver, SPUUpdaterDelegate`: forwards every callback to `SoftwareUpdater` as an `UpdateEvent`, and maps `UpdateChoice` back to `SPUUserUpdateChoice`. The other `import Sparkle` file. Kept alive by `SparkleEngine` (the delegate is weak). |
| `MMTVL/Updates/SoftwareUpdater.swift` | `@Observable final class SoftwareUpdater` (main actor): the state machine. It owns the engine, the held install block, the idle loop and the quit permission; publishes `status`; `apply(checks:mode:)`, `checkNow()`, `install()`, `installStagedForRelaunch() -> Bool`. |
| `MMTVL/Updates/UpdateRelaunchMarker.swift` | `nonisolated struct UpdateRelaunchMarker: Codable` in `~/Library/Application Support/MMTVL/update-relaunch.json`: carries "the TV is off" across an update's relaunch (L8). |
| `MMTVL/Updates/UpdatePreview.swift` (`#if DEBUG`) | `FakeUpdaterEngine` and the `-updatePreview <state>` launch argument, for screenshots and QA in `-windowed` mode (L13). |
| `MMTVL/App/AppSettings.swift` | `updateChecks = true`, `automaticUpdates = AutomaticUpdates.off`. |
| `MMTVL/App/AppDelegate.swift` | Creates and starts `SoftwareUpdater`, feeds it settings and an idle snapshot, routes Relaunch through it, restores the marker, wires Power-off (step 2) and the Restart closure (step 1). |
| `MMTVL/AVControl/PowerController.swift` | `onPowerOff` callback (step 2); `restorePoweredOff()` (step 7). |
| `MMTVL/Launcher/AppRouter.swift` | `stopPlaybackForPowerOff()` (step 2); `homeUpdateLabel` (step 8). |
| `MMTVL/Launcher/HomeView.swift` | The update capsule under the clock (step 8). |
| `MMTVL/Settings/*` | Pages `.softwareUpdate`, `.automaticUpdates`, `.confirmRestartMac`; actions; environment closures; rows (steps 1, 8). |
| `MMTVL/Settings/ThirdPartyLicenses.swift`, `MMTVL/Licenses/THIRD_PARTY_NOTICES.md` | Sparkle (step 3). |
| `scripts/release.sh`, `scripts/make-appcast.sh` (new), `scripts/test_make_appcast.sh` (new) | Nested signature and entitlement checks, the appcast (step 5). |
| `scripts/deploy-mm.sh` | Boots out Sparkle's jobs before stopping MMTVL, reads the build back (step 9). |
| `scripts/gitleaks.toml` | Allowlists the committed public key line (step 5). |

### `Config/Updater-Info.plist`

```xml
<key>SUFeedURL</key>                     <string>https://github.com/dwolcot1/mmtvl/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key>                 <string><!-- step 5: generate_keys -p --></string>
<key>SUEnableAutomaticChecks</key>       <true/>   <!-- no permission prompt; settings.json decides (L5) -->
<key>SUAllowsAutomaticUpdates</key>      <true/>   <!-- the downloads setter always works -->
<key>SUAutomaticallyUpdate</key>         <false/>  <!-- default; set from settings.json at start -->
<key>SUScheduledCheckInterval</key>      <integer>86400</integer>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SURequireSignedFeed</key>           <true/>
```

`INFOPLIST_FILE = Config/Updater-Info.plist` goes in the app target's Debug and Release configurations; `GENERATE_INFOPLIST_FILE = YES` stays. No `SUEnable*Service` keys (not sandboxed). The XPC services stay in the framework, unused (L3).

### Types (sketches)

```swift
nonisolated enum UpdateStatus: Equatable, Sendable {
    case off(OffReason)                       // .developmentBuild, .windowed
    case idle(lastChecked: Date?)             // checks on or off, nothing known
    case checking
    case upToDate(lastChecked: Date)
    case available(AvailableUpdate)           // found, not downloaded (Off mode, or Check Now)
    case downloading(AvailableUpdate, fraction: Double?)
    case installing(AvailableUpdate)          // extracting / quitting
    case ready(AvailableUpdate)               // downloaded and staged (When Idle / At Night): install block held
    case failed(UpdateFailure)                // .checkFailed, .installFailed: never an URL (L12)

    /// "Update Available: 1.4.0"; with the same marketing version, "Update Available: 1.4.0 (Build 46)" (L11).
    func homeLabel(installed: AppVersion) -> String?   // nil unless available/downloading/installing/ready
}

nonisolated struct UpdateIdleSnapshot: Equatable, Sendable {
    var mmtvlFrontmost: Bool        // NSWorkspace frontmost bundle id == ours
    var exitedToDesktop: Bool
    var mirroring: Bool             // ReflectorMonitor.isMirroring
    var poweredOffByMMTVL: Bool
    var screenSaverOurs: Bool       // screenSaver.isRunning && screenSaver.startedByMMTVL
    var stillPhase: StillScreenIdle.Phase
    var videoPlaying: Bool          // screen == .youtube || (screen == .liveTV && liveTV.isShowingVideo)
    var hour: Int                   // local hour 0…23
}

nonisolated enum UpdateIdlePolicy {
    static let nightHours = 3..<5   // "about 4 a.m." (L7)
    static func mayInstall(_ mode: AutomaticUpdates, _ s: UpdateIdleSnapshot) -> Bool {
        guard mode != .off, !s.exitedToDesktop, !s.mirroring else { return false }
        let tvOff = s.poweredOffByMMTVL && s.mmtvlFrontmost
        switch mode {
        case .off: return false
        case .whenIdle: return tvOff || s.screenSaverOurs
        case .atNight:
            guard nightHours.contains(s.hour) else { return false }
            return tvOff || s.screenSaverOurs || (s.mmtvlFrontmost && s.stillPhase != .awake && !s.videoPlaying)
        }
    }
}

protocol UpdaterEngine: AnyObject {
    func start() throws
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var sessionInProgress: Bool { get }
    var lastUpdateCheckDate: Date? { get }
    func checkForUpdates()              // user-initiated: the user driver path
    func checkForUpdateInformation()    // probe, no UI
}

/// What SparkleBridge tells SoftwareUpdater (no Sparkle types cross).
enum UpdateEvent {
    case checking
    case found(AvailableUpdate, userInitiated: Bool)   // didFindValidUpdate / showUpdateFound
    case notFound
    case failed(UpdateFailure)
    case downloadStarted, downloadProgress(Double?), extracting
    case staged(AvailableUpdate, installNow: () -> Void)   // willInstallUpdateOnQuit
    case willRelaunch                                     // updaterWillRelaunchApplication
    case dismissed                                        // dismissUpdateInstallation
}
enum UpdateChoice { case install, dismiss }
```

### How `SoftwareUpdater` behaves

**Off**
- `#if DEBUG` → `.off(.developmentBuild)`; `-windowed` → `.off(.windowed)`. The engine isn't created and nothing is requested (L4).
- Tests (the Debug test host) never start Sparkle.

**Start** (`AppDelegate`, after `startRemoteBatteryPolling()` at `:265`)
- Create the engine and apply the settings (checks first, then downloads), then call `start()`.
- With checks on and mode Off, run `checkForUpdateInformation()` once, 30 s after launch, so the home notice comes back after a relaunch (L6).
- A `start()` error → `.failed(.checkFailed)`, logged.

**`apply(checks:mode:)`** (from `applySettings`)
- `automaticallyChecksForUpdates = checks`, then `automaticallyDownloadsUpdates = checks && mode != .off`.
- Checks off → status `.idle` (keeping any `.ready`), and no home label unless an update is staged.

**Off-mode scheduled check**
- Sparkle's scheduled driver calls `showUpdateFound(userInitiated: false)` → `.found` → status `.available`, reply `.dismiss`. Sessions are never held open (L6).

**Check Now** (`checkNow()`)
- `intent = .report`, `engine.checkForUpdates()`.
- `showUpdateFound(userInitiated: true)` → `.available`, reply `.dismiss`; Settings then offers Install. `showUpdateNotFound` → `.upToDate`.

**Install** (`install()`)
- **With a held block** (`.ready`): `prepareToQuit()`, then call the block (the silent path, no Updater.app window).
- **Otherwise**: `intent = .install`, `engine.checkForUpdates()`. Then:
  1. `showUpdateFound` → `.install`
  2. download events → `.downloading`
  3. extracting → `.installing`
  4. `showReadyToInstallAndRelaunch` → `prepareToQuit()`, `.install`
- If `engine.sessionInProgress` while not `.ready` (an automatic download is under way), the row says "Downloading…" and the press does nothing.

**Automatic modes**
- Sparkle downloads silently, then `willInstallUpdateOnQuit` → `.staged(update, installNow:)` → hold the block, status `.ready`, return **true**.
- A 60-s `Task` loop (`idleLoop`) runs only while `.ready` and the mode is When Idle or At Night. Each tick builds the snapshot (an AppDelegate closure) and, if `UpdateIdlePolicy.mayInstall`:
  1. writes the marker when `poweredOffByMMTVL`;
  2. `prepareToQuit()`;
  3. calls the block;
  4. logs "Installing <version> build <build> (<reason>)".
- One attempt per staged update; on cancel, retry next tick.

**`prepareToQuit()`**
- Calls the AppDelegate closure that sets `allowsTermination = true`, so `applicationShouldTerminate` (`:1264`) lets Sparkle's quit through instead of the kiosk PIN.
- If MMTVL is still running 60 s later, the update failed: `allowsTermination` goes back to false (an AppDelegate closure), and status → `.failed(.installFailed)` with a toast "Couldn't Install the Update" (L14).

**Relaunch with a staged update**
- `installStagedForRelaunch()` calls the block and returns true. Settings → System → Relaunch MMTVL and the power menu's Relaunch try it first, else `AppRelauncher.relaunch` (L15).
- A plain quit (Restart Mac mini, logout, ⌘Q with the PIN) lets Sparkle install on quit without relaunching. That's Sparkle's behaviour, kept.

**The user driver's other callbacks**
- `show(permission)` → `SUUpdatePermissionResponse(automaticUpdateChecks: settings.updateChecks, sendSystemProfile: false)`. Not expected to be called, since `SUEnableAutomaticChecks` is set.
- Release-notes callbacks: ignored (L10).
- `showInstallingUpdate(withApplicationTerminated: false, retry)`: `prepareToQuit()`, then `retry()` once.
- `dismissUpdateInstallation`: undoes `prepareToQuit()`; status back to `.available`, or `.idle`.
- `showUpdateInFocus`: no-op.
- `showUpdaterError` / `didAbortWithError`: `.failed(...)`; logged with `(error as NSError).domain`/`.code` only.

**Delegate**
- `didFindValidUpdate` → `.found`; `updaterDidNotFindUpdate` → `.notFound`.
- `willInstallUpdateOnQuit` → `.staged`, return `mode != .off`.
- `updaterShouldRelaunchApplication` → `true`; `updaterWillRelaunchApplication` → `prepareToQuit()`, log.
- Don't implement `feedURLString(for:)`, so the user-defaults `SUFeedURL` override works for step 14.

**`onStatusChange`** → `router.settings.refreshStatus(.updates)` and `router.homeUpdateLabel = status.homeLabel(installed: .current)`.

### Power-off goes home (step 2; amends D45)

`PowerController.runOff` calls the new `onPowerOff()` **first**, before the TV and receiver are sent off. AppDelegate wires it like `onPowerOn`:
1. `router.stopPlaybackForPowerOff()`:
   - `liveTV.leave(keepingPreview: false)` when on Live TV or Multiview;
   - `youtube.pause()` on YouTube;
   - the home preview stopped until input (`stopPreviewUntilInput()`).
2. `goHomeFromAnywhere(reason: "powerOff")`: ends mirroring; other apps stay running behind MMTVL, D18.

The power menu's **Turn Off TV & Receiver** takes the same `runOff` path. Power-on is unchanged (start tile, MMTVL in front).

### The relaunch marker (L8)

`poweredOffByMMTVL` and the "TV and receiver off" sleep assertion are memory only (`PowerController.swift:179`, `:403-405`). Without them, the relaunched MMTVL would treat the next Power press as "off" when no TV is set up. So:
- before calling an idle install's block with the TV off, `SoftwareUpdater` writes `update-relaunch.json` (`{"poweredOff": true, "written": "<ISO 8601>"}`);
- at launch, `setUpPower` reads it once, deletes it, and if it's under 10 minutes old calls `power.restorePoweredOff()`, which sets `poweredOffByMMTVL = true`, `phase = .off` and `effects.keepMacAwake(true)`, and never touches the TV, receiver or displays;
- the log says "Power: still off after an update".

A corrupt or old file is deleted and ignored.

### Settings (steps 1 and 8)

**Settings → System**, MMTVL section: `Relaunch MMTVL`, **`Restart Mac mini`** (disclosure → `.confirmRestartMac`), `Exit to Desktop`. A new section **Software** above it, with one row:
- `Software Update`, showing the status in `value` ("Up to Date", "1.4.0 Available", "Downloading", "Ready to Install", "Off"), with a disclosure → `.softwareUpdate`.
- Its description: "Checks GitHub for new versions of MMTVL and installs them."

The root's System description becomes: "Accessibility access, starting at login, glass, software updates, relaunching MMTVL, restarting the Mac and leaving to the desktop."

**Restart Mac mini?** (`.confirmRestartMac`, copied from `confirmAntennaScanSections`)
- Rows: `confirm.cancel` "Cancel" → `.pop`, then `confirm.restartMac` "Restart Mac mini" → `.restartMac`.
- Footer: "Other apps are asked to quit first. With Launch at Login on, MMTVL opens again after the restart."
- The handler calls `environment.restartMac()` (→ `power.restartMac()`, which toasts on failure), then `pop()`.
- No second PIN: Settings is already behind it (user choice 2026-11-23).

**Software Update** (`.softwareUpdate`). Section 1, no title:

| Row | Shown when | Content |
|---|---|---|
| `update.installed` | always (info row) | title "Installed", value "1.4.0 Build 46" |
| `update.status` | always | by status: "Up to Date" (detail "Checked 2 hours ago", from `lastUpdateCheckDate`, relative); "Checking…"; "Couldn't Check" (detail "Check your network connection and try again."); "Updates Are Off" (detail "Development builds don't update." / "MMTVL is in a window.") |
| `update.install` | available / downloading / installing / ready | "Install MMTVL 1.5.0" → `.installUpdate`, detail "MMTVL quits and opens again in about half a minute."; downloading: value "45 %", no action; installing: "Installing…", no action; ready: "Install MMTVL 1.5.0 Now", detail "Downloaded. Installs on its own When Idle / At Night, or the next time MMTVL quits." |
| `update.checkNow` | not off, not ready, not downloading/installing | "Check Now" → `.checkForUpdates`; dimmed while `.checking` |

Section 2 "Automatic":
- `update.checks` "Check for Updates" toggle `.toggle(.updateChecks)`. Description: "Checks github.com once a day and shows a notice on the home screen when there's a new version. Check Now works either way."
- `update.mode` "Automatic Updates", value the mode's title → `.push(.automaticUpdates)`. Dimmed, with detail "Needs Check for Updates", while checks are off.

Footer: "Updates come from github.com/dwolcot1/mmtvl. Each one is checked for MMTVL's signatures before it's installed."

**Automatic Updates** (`.automaticUpdates`, copied from `glassStyleSections`): one row per case, `value: "Selected"` on the current one, action `.setAutomaticUpdates(mode)`, then pop. Descriptions:
- **Off:** "Shows a notice when there's an update. You install it here."
- **When Idle:** "Downloads updates and installs them when Power has turned the TV off, or while the screen saver is on."
- **At Night:** "Downloads updates and installs them at about 4 a.m. when nothing is playing."

Footer: "MMTVL relaunches to install an update."

New `SettingsEnvironment` closures:
- `restartMac: () -> Void`
- `updateStatus: () -> UpdateStatus`
- `lastUpdateCheck: () -> Date?`
- `checkForUpdates: () -> Void`
- `installUpdate: () -> Void`

Also `StatusParts.updates`, `SettingKey.updateChecks`, and actions `.restartMac`, `.checkForUpdates`, `.installUpdate`, `.setAutomaticUpdates(AutomaticUpdates)`.

### Home (step 8)

`AppRouter.homeUpdateLabel: String?` → `HomeView(updateLabel:)`, drawn as one more `capsule(Text(updateLabel))` right after the version capsule (`HomeView.swift:114`). It shows whether or not `showVersionOnHome` is on, and uses no new tokens.

### Local decisions

- **L1** Sparkle **2.10.1, `exactVersion`**, like MPVKit: an updater's own update is a reviewed change, not a resolve.
- **L2** Sparkle's keys in **`Config/Updater-Info.plist`**, merged through `INFOPLIST_FILE`, outside the synchronized `MMTVL/` folder. `INFOPLIST_KEY_SU…` can't work (swift-build allow-list), and inside `MMTVL/` the file would also be copied as a resource. This changes the "No Info.plist file" note in CLAUDE.md (step 11).
- **L3** **Keep Sparkle's XPC services** in the framework (unused, no `SUEnable*Service`), and check their signatures in `release.sh`. Removing them needs a run-script build phase that re-signs the framework, an extra moving part for 400 KB.
- **L4** The updater runs only in **Release builds in kiosk mode**. In Debug, a Developer ID update would pass on EdDSA alone and replace the build in `build/`. In `-windowed`, Sparkle's relaunch drops the arguments, so the window would come back as kiosk mode. Development-signed `test-build.sh` builds (Release, kiosk) do run it; they're never on the mini (memory: the MM gets notarized builds only).
- **L5** `settings.json` is the source of truth: `updateChecks` (default `true`, user choice 2026-11-23) and `automaticUpdates` (default `off`). They're mapped onto Sparkle at start and on change. Info.plist holds only defaults that stop prompts.
- **L6** Off mode never holds a Sparkle session. A found update is answered `.dismiss` and remembered in memory, and a probe 30 s after launch brings the notice back after a relaunch. Install starts a fresh user-initiated check. That's one extra small feed request, and no long-held continuations.
- **L7** "At Night" is **03:00–05:00 local**, and also accepts a dimmed MMTVL still screen with nothing playing. "When Idle" is TV-off-by-Power (MMTVL in front) or MMTVL's own screen saver (user choices 2026-11-23). Neither installs during mirroring or after Exit to Desktop.
- **L8** An idle install during Power-off carries **"the TV is off"** across the relaunch in `update-relaunch.json` (10 minutes, deleted on read), so the next Power press turns things on.
- **L9** **No delta updates**: a one-item appcast written by our own `scripts/make-appcast.sh`, not `generate_appcast`. Clients need only the newest item, and a hand-made feed is deterministic and testable.
- **L10** **No release notes in the appcast or on the TV**: no `releaseNotesLink`, no `description`. The notes are Markdown with install lines and checksums, meant for the web page, and with signed feeds linked notes would need signing too.
- **L11** The home label is "Update Available: <version>". When the versions are equal (test builds), it appends " (Build <N>)".
- **L12** Errors show and log **no URL**: Settings says "Couldn't Check" / "Couldn't Install the Update", and the log has the NSError domain and code plus the host `github.com`. Sparkle's `localizedDescription` can contain the feed URL.
- **L13** `-updatePreview available|downloading|ready|checking|failed|upToDate` (**Debug only**) puts a `FakeUpdaterEngine` behind `SoftwareUpdater` with that state, so the page and the home capsule can be seen in `-windowed`.
- **L14** The quit permission is lifted only for the install and **taken back after 60 s** if MMTVL is still running, so a failed install doesn't leave ⌘Q without the PIN.
- **L15** Relaunch with a staged update **installs it** (Settings and the power menu), since Sparkle would install it at that quit anyway, and this way MMTVL comes back.
- **L16** Power-off stops MMTVL's own playback and goes home **before** the TV is told to turn off (user, 2026-11-23). Other apps keep running behind it (D18).
- **L17** The Restart row's wording matches the power menu's "Restart Mac mini", whatever the Mac is.

## Implementation steps

- [x] **1. Restart Mac mini in Settings → System** `[implementer]`, files: `MMTVL/Settings/SettingsTypes.swift`, `MMTVL/Settings/SettingsModel+Pages.swift`, `MMTVL/Settings/SettingsModel.swift`, `MMTVL/Settings/SettingsEnvironment.swift`, `MMTVL/App/AppDelegate.swift` (`makeSettingsEnvironment`, `:1455`), `MMTVLTests/SettingsTestSupport.swift`, `MMTVLTests/SettingsModelTests.swift`
  - Add the page `.confirmRestartMac` with the title "Restart Mac mini?", the action `.restartMac`, and the environment closure `restartMac: () -> Void`. AppDelegate passes `{ [weak self] in self?.power?.restartMac() }`.
  - Add the row between Relaunch and Exit to Desktop (`SettingsModel+Pages.swift:291-294`). Build the confirm page and its handler exactly as *Design → Settings*, copying `confirmAntennaScanSections` and `SettingsModel.swift:475-479`.
  - Update the System description (`:188-189`) to the text in *Design*, minus "software updates" until step 8.
  - Add `restarts: Int` to `SettingsRecorder`.
  - Tests in `SettingsModelTests`:
    - `systemHasRestartRow`: the row is between `relaunch` and `exit`, with a disclosure.
    - `restartConfirmCancelPops`: Cancel returns to System with no restart.
    - `restartConfirmRestarts`: Restart calls `restartMac` once and pops.
  - Done when: `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test` passes (quote the result line). In `open build/Build/Products/Debug/MMTVL.app --args -windowed YES`, Settings → System shows Restart Mac mini, and its page shows Cancel first. **Don't select Restart on the dev Mac.**
  - **Done 2026-11-23** (`945a77a`). Full suite: "✔ Test run with 2112 tests in 186 suites passed after 14.654 seconds." QA PASS: the model tests check the row order, the disclosure, the page with Cancel focused first, and the footer; nobody looked at the running app (driving it near Restart was judged unsafe), so that look is a human check. The QA minor (no description) was fixed by the user's choice: the row's description is "Restarts the Mac mini. Asks first." (see *Deviations*).

- [ ] **2. Power-off stops playback and goes home** `[implementer]`, files: `MMTVL/AVControl/PowerController.swift`, `MMTVL/App/AppDelegate.swift` (`setUpPower`, `:670-700`), `MMTVL/Launcher/AppRouter.swift`, `MMTVLTests/PowerControllerTests.swift` (or the suite that tests `PowerController` today), `MMTVLTests/AppRouter…Tests.swift` (the suite that tests `goHome`)
  - Add `var onPowerOff: () -> Void = {}` to `PowerController` and call it at the top of `runOff` (`:300`), before the TV/receiver commands.
  - Add `AppRouter.stopPlaybackForPowerOff()`: Live TV or Multiview → `liveTV.leave(keepingPreview: false)`; YouTube → `youtube.pause()`; then stop the preview until input (`stopPreviewUntilInput()`, `:426`).
  - In `setUpPower`: `power.onPowerOff = { [weak self] in self?.router?.stopPlaybackForPowerOff(); self?.goHomeFromAnywhere(reason: "powerOff") }`.
  - Log at notice level (category `Power`): "Power: stopped playback, home".
  - Tests:
    - `powerOffCallsOnPowerOffFirst`: the fake effects record that `onPowerOff` ran before `sleepDisplays`.
    - `powerOnDoesntCallOnPowerOff`.
    - Router: `powerOffLeavesLiveTVWithoutPreview` (screen `.home`, the preview not playing) and `powerOffPausesYouTube`.
  - Done when: the full suite passes. Code review shows Turn Off TV & Receiver (power menu) goes through the same `runOff`.

- [ ] **3. Sparkle package, partial Info.plist, licenses** `[implementer]` `[security]`, files: `MMTVL.xcodeproj/project.pbxproj`, `MMTVL.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, `Config/Updater-Info.plist` (new), `MMTVL/Settings/ThirdPartyLicenses.swift`, `MMTVL/Licenses/THIRD_PARTY_NOTICES.md`
  - Add `https://github.com/sparkle-project/Sparkle`, **exactVersion 2.10.1**, product `Sparkle`, to the **app target only**, the way MPVKit is referenced (`project.pbxproj:400-428`, `:99-102`, `:43-51`). It must be embedded (Embed & Sign); Xcode does this for a binary framework added to the app.
  - Create `Config/Updater-Info.plist` with every key in *Design* **except `SUPublicEDKey`** (step 5). Set `INFOPLIST_FILE = Config/Updater-Info.plist` in the app target's Debug and Release configurations. Keep `GENERATE_INFOPLIST_FILE = YES`.
  - No code imports Sparkle yet.
  - Licenses: one component `sparkle` / "Sparkle" / `2.10.1` / `MIT` / its copyright line / `https://github.com/sparkle-project/Sparkle` / `frameworks: ["Sparkle"]`, in sorted position.
    - In the notices, add a `### Sparkle` entry and its full `LICENSE` text, *External licenses* section included (bsdiff, sais-lite, ed25519, SUSignatureVerifier), under `## License texts`.
    - Reword `THIRD_PARTY_NOTICES.md:43-44` and `ThirdPartyLicenses.swift:26-28`: Sparkle is a real dynamic framework; the others stay placeholders.
  - Done when all of these hold:
    - The full suite passes, including `ThirdPartyLicensesTests`.
    - `/usr/libexec/PlistBuddy -c 'Print SUFeedURL' -c 'Print NSLocalNetworkUsageDescription' build/Build/Products/Debug/MMTVL.app/Contents/Info.plist` prints both.
    - `ls build/Build/Products/Debug/MMTVL.app/Contents/Frameworks/Sparkle.framework/Versions/B/` lists `Autoupdate` and `Updater.app`.
    - `ls build/SourcePackages/artifacts/sparkle/Sparkle/bin/` lists `generate_keys` and `sign_update`. Record the real path in *Research & findings* if it differs.

- [ ] **4. EdDSA keys** `[human]` (the user, in a Terminal on this Mac; the Keychain may ask)
  - Run `build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`. It creates the key in the login Keychain (service `https://sparkle-project.org`, account `ed25519`) and prints the public key. If a key exists already, it only prints it.
  - Back it up: `…/generate_keys -x ~/Desktop/mmtvl-sparkle-ed25519.txt`. Store the file's contents in your password manager, then delete the file. **Never in the repo, the scratchpad or any chat.** Losing it means existing installs can't update until the next Developer ID change (rotation rule above).
  - Give the orchestrator the **public** key: `…/generate_keys -p`.
  - Done when: the public key is in the conversation and the user confirms the backup exists.

- [ ] **5. Public key, appcast, release checks** `[implementer]` `[security]`, files: `Config/Updater-Info.plist`, `scripts/make-appcast.sh` (new), `scripts/test_make_appcast.sh` (new), `scripts/release.sh`, `scripts/gitleaks.toml`
  - **Public key:** put it in `SUPublicEDKey`. Allowlist that exact line in `gitleaks.toml` (a `[[allowlists]]` with `paths = ['''Config/Updater-Info.plist''']` and a regex for the 44-character value), and confirm: `gitleaks dir --config scripts/gitleaks.toml --redact --no-banner Config`.
  - **`scripts/make-appcast.sh <zip> <tag> <version> <build> <out.xml>`** (zsh, `set -euo pipefail`) writes the one-item feed in *Research & findings* → Appcast:
    - title "MMTVL <version>", RFC 822 `pubDate`, `sparkle:version` = build, `sparkle:shortVersionString` = version, `sparkle:minimumSystemVersion` `26.0.0`;
    - `<link>https://github.com/dwolcot1/mmtvl/releases/tag/<tag></link>`;
    - an enclosure at `https://github.com/dwolcot1/mmtvl/releases/download/<tag>/<zip name>` with `length` and `sparkle:edSignature` from `sign_update <zip>`;
    - then `sign_update <out.xml>` signs the feed;
    - it checks `xmllint --noout` and `sign_update --verify <zip> <sig>`.
    - The tools come from `MMTVL_SPARKLE_BIN` or else release's derived data (`build/release/…/SourcePackages/artifacts/sparkle/Sparkle/bin`, or the step 3 path; find which `-derivedDataPath` release.sh archives with).
    - `MMTVL_APPCAST_UNSIGNED=1` skips both signatures, for the test only.
  - **`scripts/test_make_appcast.sh`:** runs make-appcast unsigned on a dummy zip in a temp dir, and asserts with `xmllint --xpath`: version, build, the enclosure URL, length = the file size, `minimumSystemVersion`, no `description`/`releaseNotesLink`. It prints "make-appcast: N checks passed".
  - **`scripts/release.sh`:**
    - (a) Run `check_signature` on **every nested code item**: each `*.framework`, `*.app`, `*.xpc` under `Contents/Frameworks`, and each Mach-O file (`file -b | grep -q Mach-O`) under them. Print "N code items checked".
    - (b) Check entitlements **per item**: the app = the existing allowlist; Autoupdate = exactly what the export inspection below found (expected none, or only `com.apple.application-identifier`; anything else fails); every other item = none.
    - (c) Zip with `ditto -c -k --sequesterRsrc --keepParent`.
    - (d) After the zip, run `make-appcast.sh "$zip" "${MMTVL_RELEASE_TAG:-v$version}" "$version" "$next" "$out/appcast.xml"` and print "Appcast: …/appcast.xml (tag <tag>)".
    - Nothing else changes: no tagging, pushing or publishing.
  - **Export inspection** (no notarization, no build bump):
    1. `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -configuration Release -derivedDataPath build archive -archivePath <scratchpad>/m15.xcarchive`
    2. `xcodebuild -exportArchive -archivePath <scratchpad>/m15.xcarchive -exportOptionsPlist scripts/ExportOptions.plist -exportPath <scratchpad>/export -allowProvisioningUpdates`
    3. `codesign -dvv` and `codesign -d --entitlements -` on Autoupdate, Updater.app, both XPCs and the framework.
    - Record each item's Authority, TeamIdentifier, flags and entitlements under *Research & findings*. If the shell can't reach the signing key (errSecInternalComponent, `release.sh:94-97`), hand these two commands to the user as `!` commands.
    - **If any helper isn't Developer ID + runtime, or Autoupdate keeps an entitlement that needs a provisioning profile, stop and record it under *Deviations & questions*.**
  - Done when: `zsh scripts/test_make_appcast.sh` passes; the export inspection is recorded; `zsh -n scripts/release.sh` is clean; the full Xcode suite passes. The real signed path runs in step 13.

- [ ] **6. Settings keys and the idle policy** `[implementer]`, files: `MMTVL/Updates/AutomaticUpdates.swift`, `MMTVL/Updates/UpdateStatus.swift`, `MMTVL/Updates/UpdateIdlePolicy.swift` (all new), `MMTVL/App/AppSettings.swift`, `MMTVLTests/AppSettingsTests.swift`, `MMTVLTests/UpdateIdlePolicyTests.swift` (new), `MMTVLTests/UpdateStatusTests.swift` (new)
  - Implement the types in *Design → Types*.
  - In `AppSettings`: `var updateChecks = true`, `var automaticUpdates = AutomaticUpdates.off`, decoded like `glassStyle` (`:167-168`); unknown values read as `.off`.
  - Tests:
    - `AppSettingsTests.updateSettingsDefaultAndDecode`: an empty object gives `true` / `.off`; `"whenIdle"` and `"atNight"` decode; `"weekly"` reads `.off`; `updateChecks: false` decodes.
    - `UpdateIdlePolicyTests`: `offNeverInstalls`, `whenIdleAfterPowerOff`, `whenIdleNotWhenOtherAppFront`, `whenIdleDuringOurScreenSaver`, `whenIdleNotForOthersScreenSaver`, `notWhileMirroring`, `notAfterExitToDesktop`, `atNightOnlyBetween3And5`, `atNightOnDimmedStillScreen`, `atNightNotWhileVideoPlays`, `atNightAfterPowerOffEvenAt4`.
    - `UpdateStatusTests`: `homeLabelForAvailable` ("Update Available: 1.5.0"), `homeLabelSameVersionAddsBuild`, `homeLabelNilWhenUpToDate`, `homeLabelForReady`.
  - Done when: the full suite passes.

- [ ] **7. `SoftwareUpdater`, Sparkle bridge, AppDelegate wiring** `[implementer]` `[security]`, files: `MMTVL/Updates/UpdaterEngine.swift`, `MMTVL/Updates/SparkleBridge.swift`, `MMTVL/Updates/SoftwareUpdater.swift`, `MMTVL/Updates/UpdateRelaunchMarker.swift`, `MMTVL/Updates/UpdatePreview.swift` (all new), `MMTVL/AVControl/PowerController.swift`, `MMTVL/App/AppDelegate.swift`, `MMTVLTests/SoftwareUpdaterTests.swift` (new), `MMTVLTests/UpdateRelaunchMarkerTests.swift` (new), `MMTVLTests/PowerControllerTests.swift`
  - Implement *Design → How `SoftwareUpdater` behaves*.
    - Only `UpdaterEngine.swift` (`SparkleEngine`) and `SparkleBridge.swift` import Sparkle.
    - `SparkleEngine` creates `SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: bridge, delegate: bridge)` and keeps the bridge strongly.
    - The bridge's `async` user-driver methods `await` the updater's answer.
  - Logger category **`Updater`**, at notice level:
    - "Checking for updates (github.com)"
    - "Update available: <version> build <build>" / "Up to date"
    - "Downloaded <version> build <build>; installs <mode>"
    - "Installing <version> build <build> (<reason>)"
    - "Couldn't check: <domain> <code>"
    - "Install didn't finish; quit allowed again"
    - **No URLs.**
  - AppDelegate:
    - Create the updater after `startRemoteBatteryPolling()` (`:265`), Release + kiosk only (L4), else `.off(reason)`.
    - Pass it `allowQuit: { self?.allowsTermination = true }`, `revokeQuit: { self?.allowsTermination = false }`, `snapshot: { … }` (fields in *Design*; `hour` from `Calendar.current`) and `writeMarker`.
    - Apply settings at start and in `applySettings` when `updateChecks` or `automaticUpdates` change.
    - Route both relaunch closures (`:675`, `:1471`) through `installStagedForRelaunch()` first.
    - Cancel the idle loop in `applicationWillTerminate`.
  - PowerController: `restorePoweredOff()` as in *Design → The relaunch marker*. `setUpPower` reads, deletes and applies the marker.
  - `UpdatePreview` (Debug): `-updatePreview <state>` creates `SoftwareUpdater` with `FakeUpdaterEngine` in that state, also in `-windowed`.
  - Tests (`SoftwareUpdaterTests`, all with a `FakeUpdaterEngine`):
    - `developmentBuildIsOff`
    - `applySetsChecksBeforeDownloads` (the fake records order; checks off → downloads off)
    - `offModeScheduledFindIsDismissedAndAvailable`
    - `checkNowReportsAvailable`
    - `checkNowUpToDate`
    - `installStartsUserCheckAndAnswersInstall`
    - `readyToInstallAllowsQuitFirst` (`allowQuit` before `.install`)
    - `stagedBlockHeldInAutomaticModes`
    - `stagedRefusedInOffMode` (returns false)
    - `installWithStagedCallsBlock`
    - `idleTickInstallsWhenPolicyAllows`
    - `idleTickWaitsOtherwise`
    - `markerWrittenOnlyWhenPoweredOff`
    - `quitRevokedAfter60s` (the injected clock advances)
    - `relaunchWithStagedInstalls`
    - `relaunchWithoutStagedReturnsFalse`
    - `errorsCarryNoURL` (a failure built from an `NSError` whose description has a URL leaves no "http" in status texts)
    - `homeLabelPublished`
  - `UpdateRelaunchMarkerTests`: `roundTrip`, `olderThan10MinutesIgnored`, `corruptFileDeletedAndIgnored`, `deletedAfterRead`.
  - `PowerControllerTests.restorePoweredOffNeverSendsCommands` (the next `powerButton()` with no TV set up turns things **on**).
  - Done when:
    - The full suite passes.
    - The Debug app launched `-windowed YES -updatePreview available` logs (category `Updater`) the fake's state.
    - A **Release** build (`xcodebuild … -configuration Release -derivedDataPath build build`) launched with `-windowed YES` logs that updates are off in a window and makes no request (`log show --last 5m --predicate 'subsystem == "dev.mmtvl.launcher" AND category == "Updater"' --info`).

- [ ] **8. Software Update page, Automatic Updates page, home notice** `[implementer]`, files: `MMTVL/Settings/SettingsTypes.swift`, `MMTVL/Settings/SettingsModel+Pages.swift`, `MMTVL/Settings/SettingsModel.swift`, `MMTVL/Settings/SettingsEnvironment.swift`, `MMTVL/App/AppDelegate.swift`, `MMTVL/Launcher/AppRouter.swift`, `MMTVL/Launcher/HomeView.swift`, `MMTVLTests/SettingsTestSupport.swift`, `MMTVLTests/SettingsModelTests.swift`
  - Build *Design → Settings* and *Design → Home*.
    - `SettingsEnvironment` gets the update closures; `StatusParts.updates`; `updater.onStatusChange` → `router?.settings.refreshStatus(.updates)` and `router?.homeUpdateLabel = …`.
    - Add "software updates" to the System description.
  - Tests:
    - `softwareUpdateRowOnSystem`: the value follows the status.
    - `softwareUpdatePageUpToDate`, `softwareUpdatePageAvailableOffersInstall`, `softwareUpdatePageDownloadingShowsPercent`, `softwareUpdatePageReadyInstallNow`, `softwareUpdatePageOff`.
    - `checkNowCallsEnvironment`, `installCallsEnvironment`.
    - `checksToggleSavesUpdateChecks`.
    - `automaticUpdatesChoiceSetsAndPops`.
    - `automaticUpdatesDimmedWhenChecksOff`.
    - `copyDoesntRepeatDescriptions` still passes (`:118`).
  - Done when: the full suite passes. Screenshots of `-windowed YES -updatePreview available`, `… ready` and `… upToDate` show the home capsule under the clock ("Update Available: …" for the first two) and the Software Update page with the rows above. Attach the screenshots to the QA report.

- [ ] **9. `deploy-mm.sh` and staged updates** `[implementer]`, files: `scripts/deploy-mm.sh`
  - Before `stop_mmtvl` in `install_zip` (`:93-105`) and on `--rollback`, remove Sparkle's jobs on the mini so a staged update can't install over the deployed build:
    `launchctl bootout gui/$(id -u)/dev.mmtvl.launcher-sparkle-updater 2>/dev/null; launchctl bootout gui/$(id -u)/dev.mmtvl.launcher-sparkle-progress 2>/dev/null; true`.
    - If step 14 G shows the jobs live in `user/<uid>`, use that domain (recorded as a deviation).
  - After `start_mmtvl`, read the installed `CFBundleVersion` back and fail with one line if it isn't the expected build.
  - Done when: `zsh -n scripts/deploy-mm.sh` is clean and the diff is reviewed. It runs for real in step 14.

- [ ] **10. Visual check** `[designer]`, files: none, or only `HomeView.swift` / the Settings rows if something is off
  - With the step 8 screenshots and `-windowed YES -updatePreview …`, check:
    - the update capsule matches the version capsule (font, glass, spacing, right-aligned);
    - the Software Update page follows D42 (row capsules, the description band, no new tokens);
    - the Restart confirm page matches Scan for Channels.
  - Done when: the designer reports PASS with screenshots, or a list of fixes that an implementer pass applies.

- [ ] **11. Docs** `[doc]`, files: `CLAUDE.md`, `README.md`, `docs/plans/MASTER_PLAN.md`, `MMTVL/Licenses/THIRD_PARTY_NOTICES.md` (if step 3 missed anything), this plan
  - **CLAUDE.md, Project setup notes:**
    - "No Info.plist file" → the generated plist plus `Config/Updater-Info.plist` (Sparkle's keys only, merged by `INFOPLIST_FILE`).
    - Swift packages: **Sparkle 2.10.1** (exact, app target).
    - Release checklist:
      1. `scripts/release.sh` also writes `build/release/appcast.xml` (tag from `MMTVL_RELEASE_TAG`, default `v<version>`);
      2. `gh release create v<version> <zip> build/release/appcast.xml --draft …`;
      3. after publishing, read back `curl -sL https://github.com/dwolcot1/mmtvl/releases/latest/download/appcast.xml | grep -E 'sparkle:(version|shortVersionString)'`.
    - The EdDSA key: login Keychain `https://sparkle-project.org` / `ed25519`, backed up by the user, never in the repo.
    - `deploy-mm.sh` boots out Sparkle's jobs.
  - **CLAUDE.md, Conventions → `settings.json`:**
    - `updateChecks` (Settings → System → Software Update → Check for Updates; default `true`).
    - `automaticUpdates` (`off` default | `whenIdle` | `atNight`; unknown values read as `off`).
    - New file `update-relaunch.json` (L8).
    - Sparkle's own `SU*` user defaults in `dev.mmtvl.launcher` (e.g. `defaults delete dev.mmtvl.launcher SULastCheckTime` forces a check at the next launch).
    - The test-only `defaults write dev.mmtvl.launcher SUFeedURL <url>` and its `defaults delete`.
  - **CLAUDE.md, Commands:** a `log show` line for category `Updater` plus Sparkle's processes:
    `/usr/bin/log show --last 1h --predicate '(subsystem == "dev.mmtvl.launcher" AND category == "Updater") OR process == "Autoupdate" OR process == "Updater"' --info`.
  - **CLAUDE.md, Power:** Power-off stops playback and goes home (L16).
  - **README:** replace `:29` with automatic updates from 1.4.0 (Settings → System → Software Update), and a one-time manual install for 1.3.x.
  - **Master plan:** M15 row → In progress/Done as appropriate; Q35 answered from step 14.
  - Done when: `git diff --stat` shows the files above and the gitleaks dir scans of `docs` and `scripts` are clean.

- [ ] **12. Security review** `[security]` (`security-reviewer`, threshold: medium and above blocks; stop when every finding is fixed or accepted by the user)
  - Scope: the diffs of steps 3, 5, 7 and 9: the new package and its helpers, `Config/Updater-Info.plist` (feed integrity, signed feed, `SUVerifyUpdateBeforeExtraction`), the `SUFeedURL` user-defaults override, `release.sh`'s signature and entitlement checks, the quit-permission lift and revoke (kiosk lock, D36), the relaunch marker, logs without URLs, and `deploy-mm.sh`.
  - Done when: the review's findings are fixed by an implementer pass (QA again) or recorded as accepted by the user.

- [ ] **13. Builds A and B** `[release]` (each release needs the user's yes; the release agent follows the CLAUDE.md checklist)
  - **A:**
    1. `MARKETING_VERSION` 1.3.1 → **1.4.0** (all four configurations), committed on a clean `master`.
    2. `scripts/release.sh` from Terminal (notarization, possibly hours).
    3. Commit the bump as "Build <N>".
    4. Read the zip back (`stapler validate`, `spctl`, SHA-256) and `build/release/appcast.xml` (version N, `sign_update --verify` the zip).
    5. Create the **draft** `v1.4.0` with the zip and `appcast.xml`. **Not published** until step 14 passes.
  - **B:**
    1. On a clean `master` again: `MMTVL_RELEASE_TAG=v1.4.0-update-test scripts/release.sh` (build N+1), then commit "Build <N+1>".
    2. Publish **prerelease** `v1.4.0-update-test` (`--prerelease --latest=false`) with the zip and `appcast.xml`.
    3. Read back: `gh release list -L 3` (Latest still `v1.3.1`), and `curl -sIL https://github.com/dwolcot1/mmtvl/releases/download/v1.4.0-update-test/appcast.xml` (200 after redirects).
  - Gitleaks before each push (CLAUDE.md).
  - Done when: both zips and appcasts are read back. A's draft and B's prerelease exist (`gh release view`).

- [ ] **14. On the Mac mini and the TV** `[human]` (one session; receiver at −75 dB, TV and receiver off when done)
  - **Before:**
    1. `ssh mm "ls -ld /Applications/MMTVL.app"`: the owner should be the logged-in user (Q35).
    2. `scripts/deploy-mm.sh build/release/MMTVL-1.4.0-build<N>.zip` (A).
    3. `ssh mm "defaults write dev.mmtvl.launcher SUFeedURL 'https://github.com/dwolcot1/mmtvl/releases/download/v1.4.0-update-test/appcast.xml'"`, then relaunch MMTVL (Settings → System → Relaunch).
  - Log on the Mac: `ssh mm "/usr/bin/log show --last 30m --predicate '(subsystem == \"dev.mmtvl.launcher\" AND (category == \"Updater\" OR category == \"Power\")) OR process == \"Autoupdate\" OR process == \"Updater\"' --info"`.
  - **A. Restart:** Settings → System → Restart Mac mini → Cancel goes back. Restart → the mini restarts and MMTVL opens after login (Launch at Login on). Note anything that asked a question on screen.
  - **B. Power-off goes home:**
    - With a Live TV channel playing, Power → TV and receiver off; then Power → home screen, no Live TV stream (no "Playing after" line in the MPV log after the off).
    - With YouTube playing: the same, and YouTube is paused when reopened.
    - With Plex HTPC playing: Power off, wait a minute, Power on → MMTVL's home screen. Open Plex: **did playback keep going** (the position moved on) or pause? Note it.
  - **C. Manual install (Automatic Updates: Off):**
    - Within about 30 s of launch, the home screen shows "Update Available: 1.4.0 (Build N+1)", and Settings → System → Software Update shows it.
    - Install → MMTVL quits. Note **what the TV shows meanwhile** (desktop, a Sparkle progress window, how long).
    - MMTVL comes back on its own within ~30 s. Settings → About shows build N+1.
    - Still working: Home from Plex (Accessibility), Live TV loads with **no Keychain prompt**, the phone remote is still paired, and Settings → System → Launch at Login is still on.
  - **D. Rollback:** `scripts/deploy-mm.sh --rollback` installs A again. Note that the bootout lines ran quietly.
  - **E. When Idle with Power:**
    - Set Automatic Updates: When Idle, then `ssh mm "defaults delete dev.mmtvl.launcher SULastCheckTime"` and Relaunch.
    - Wait for "Downloaded … installs When Idle" in the log; Settings shows Ready to Install.
    - Power off. Within ~2 minutes the log shows "Installing … (power off)", then the relaunch. **The TV and receiver stay off** (note if the TV wakes).
    - Power on → TV and receiver on, home screen, About = N+1.
  - **F. When Idle with the screen saver:** rollback again (D), wait for Ready, leave the home screen alone ~10 minutes (dim, then the screen saver). It installs during the saver; note what shows after the relaunch (saver still on, or the home screen).
  - **G. A staged update vs deploy-mm.sh:**
    - Rollback, wait for Ready, then `ssh mm "launchctl print gui/\$(id -u) | grep -i sparkle"`; note the job names and domain.
    - Run `scripts/deploy-mm.sh build/release/MMTVL-1.4.0-build<N>.zip` (A over A). Afterwards About must still show **N**, not N+1.
  - **H. Check for Updates off:** turn it off, relaunch, and confirm the log shows no "Checking for updates" for a few minutes and the home notice is gone. Turn it back on.
  - **(Optional) At Night:** leave Ready + At Night overnight, and read the log the next morning ("Installing … (night)" between 03:00 and 05:00).
  - **After:** `ssh mm "defaults delete dev.mmtvl.launcher SUFeedURL"`; set the mode you want. TV and receiver off.
  - Done when: the user reports A–H. Each failure goes to *Deviations & questions* with the log lines.

- [ ] **15. Publish 1.4.0** `[release]` (after the user's yes)
  - Publish the draft `v1.4.0` (A). Read back: `gh release view v1.4.0` (Latest) and `curl -sL https://github.com/dwolcot1/mmtvl/releases/latest/download/appcast.xml | grep -E 'sparkle:(version|shortVersionString)'` (1.4.0, build N).
  - Ask the user whether to delete the `v1.4.0-update-test` prerelease and its tag, or keep it.
  - The mini is on N+1, so it isn't offered N (Sparkle refuses downgrades).
  - Done when: read back; the master plan's M15 row → Done; this plan → `docs/plans/archive/` (`git mv`, links fixed).

## Tests

- **New suites:** `UpdateIdlePolicyTests`, `UpdateStatusTests`, `SoftwareUpdaterTests`, `UpdateRelaunchMarkerTests` (steps 6–7; test names there).
- **Extended suites:** `SettingsModelTests` (steps 1, 8), `AppSettingsTests` (step 6), `PowerControllerTests` and the router suite (steps 2, 7), `ThirdPartyLicensesTests` (unchanged code; step 3 must keep it green).
- **Script test:** `zsh scripts/test_make_appcast.sh` (step 5).
- **Commands:**
  - Full suite: `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`.
  - One suite: `-only-testing:MMTVLTests/SoftwareUpdaterTests`.
  - Release build: `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -configuration Release -derivedDataPath build build`.
- Quote the result line after the last fix of each step.

## Manual verification

**On this Mac (`-windowed YES`):**
- Settings → System has Software Update and Restart Mac mini. Restart's page has Cancel first; **don't select Restart**.
- `-updatePreview available` / `ready` / `upToDate`: the home capsule and the page rows.
- A Release build in `-windowed` logs that updates are off and makes no request.
- `zsh scripts/test_make_appcast.sh`.

**On the MM and the TV:** step 14, A–H.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| Export doesn't sign Sparkle's helpers with Developer ID + runtime, or Autoupdate keeps `com.apple.application-identifier` and macOS won't launch it without a profile | Step 5 inspection; notarization rejects; Autoupdate killed (log `AMFI`) | Re-sign the helpers in `release.sh` before notarizing (Sparkle docs/sandboxing:75-90, per binary, `-o runtime`, never `--deep`), stripping that entitlement; record it in D58 |
| `INFOPLIST_FILE` collides with the synchronized folder or loses generated keys | Build error "Multiple commands produce"; a missing `NSLocalNetworkUsageDescription` | The plist is outside `MMTVL/` already; else a membership exception, or move the generated keys into the file |
| Updater.app's progress window shows on the TV during a manual Install | Step 14 C | Route Install through the silent path: turn on `automaticallyDownloadsUpdates` for that one check, then call the held block (a later change, after the user decides) |
| An update asks for an admin password (not writable), which the remote can't answer | Step 14 / Q35; a dialog on the TV | Settings says to reinstall MMTVL into `/Applications` as the logged-in user; the silent path never asks |
| A staged update installs over a deploy | Step 14 G shows N+1 after deploying N | Step 9's bootout (fix the domain); or quit by SIGKILL after the bootout |
| The kiosk quit guard blocks Sparkle's quit | The install hangs; log "Install didn't finish" | `prepareToQuit()` runs before every install path (tests); check `isLockEffective` handling |
| The relaunch during Power-off wakes the TV or displays | Step 14 E | Delay the window's show until input after a marker restore (a follow-up step) |
| Plex keeps playing behind MMTVL after Power-off | Step 14 B | The user decides: pause by media key before Home, or accept |
| The EdDSA key is lost | `generate_keys -p` finds nothing | Restore from the backup (`generate_keys -f`); else rotate by changing the key with the same Developer ID certificate (docs/index:129) |
| GitHub's `latest/download` stops resolving, or a Roku release takes Latest | The feed 404s; "Couldn't Check" for everyone | Roku stays `--latest=false` (D57); else move the feed to a fixed URL in a later release (users on the old feed need one manual update) |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.

- **2026-11-23, step 1:** the Design gave the Restart Mac mini row no description, so the bottom band would be empty (Relaunch and Exit have one). The user chose to add "Restarts the Mac mini. Asks first."; `systemHasRestartRow` asserts it.
