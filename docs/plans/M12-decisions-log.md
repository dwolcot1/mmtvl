# M12 decisions log (automated run)

From 2026-11-22 the remaining off-device steps of M12 (18, 19, 20, 21, 22, 24, 25) run automated while the user is away. Every decision made without the user is recorded here:

- what was chosen;
- why;
- a plain explanation;
- pros and cons.

The user can reverse any of them. Decisions the user made themselves are marked **User**; the rest are **Recommended**, the default the orchestrator took.

The sub plan's *Deviations & questions* section keeps the QA and security notes per step, and links here.

## How to read an entry

Each entry has:

- **Step:** the step it belongs to.
- **Decision:** what was chosen.
- **Why:** the reason.
- **Explained:** what it means in plain terms.
- **Pros / Cons**
- **To reverse:** what changing it would take.

---

## User choices before the run (2026-11-22)

### U1. Antenna without probe results: build every path, gated
- **Step:** 21. **Decision (User):** Build every discovery method plus a typed address, play H.264 always, and play MPEG-2 only where the Roku reports it can decode it. Each choice that step 4 is meant to settle sits behind one switch.
- **Why:** Step 4's probes (discovery, raw MPEG-TS, MPEG-2, the SiliconDust guide format) need a Roku, and none is available yet.
- **Explained:** The antenna code is written as if every probe might pass. When the probes run, the ones that fail are switched off rather than rebuilt.
- **Pros:** No rebuild after the probes. Step 23 can test everything in one sitting.
- **Cons:** Some code may never be used, and more code goes through the security review.
- **To reverse:** Remove the paths step 4 rules out.

### U2. Git: push each step, a PR per phase, squash-merge at the end
- **Decision (User):**
  1. After QA, each step is committed and its branch pushed.
  2. Each finished phase gets a PR, stacked on the phase before it.
  3. Once phase 6's automated steps are done, every gate runs again, and the PRs are squash-merged into `master` in order: #1, #2, then phases 2–6. Each is rebased onto `master` first.
- **Why:** The user's instruction ("push branches, pr at every phase, squash merge when complete"), with merging at the end. The repo has no CI, so "green" means the orchestrator's own gate runs plus QA.
- **Explained:** Device checks (steps 1, 4, 15, 23) stay open in the plan. Merging doesn't claim they passed.
- **Pros:** One merge session, with the whole stack reviewed and gated together.
- **Cons:** `master` gets Roku code that hasn't run on a Roku yet. It is self-contained in `roku/`, plus MMTVL test files only.

### U3. pen.dev's `fileToken` is allowlisted
- **Decision (User):** gitleaks flagged a `fileToken` line in `design/roku-live-tv.pen`, on public branches since step 10. The user judged it harmless, so a narrow allowlist entry now covers that line only. The same commit allowlists M12's made-up test credentials.
- **Explained:** pen.dev writes `fileToken` into the file's metadata. It isn't on any design node.
- **Pros:** No history rewrite, and scans are clean again.
- **Cons:** If pen.dev ever used it for access, it would be public. The user is satisfied it doesn't.

### U4. This log
- **Decision (User):** Decisions go in this file, `docs/plans/M12-decisions-log.md`, linked from the sub plan.

---

## Decisions during the run

*(Added as each step is built.)*

### D1. Choose Teams lists MMTVL's leagues, not the design frame's
- **Step:** 18. **Decision (Recommended):** The picker shows MMTVL's 8 leagues, with MMTVL's names and in MMTVL's order: NFL, NBA, NHL, MLB, College Football, College Basketball, Women's College Basketball, College Baseball.
- **Why:** Frame P9pORE shows WNBA, MLS and "Men's College Basketball", but MMTVL's team catalog has none of these. The Roku app has to match MMTVL, and the catalog is copied from MMTVL.
- **Explained:** The frame was a picture of the layout, and its league names were placeholders. The layout and the check mark are kept; the names come from the data.
- **Pros:**
  - Same leagues as on the Mac.
  - No league that would open empty.
- **Cons:**
  - The frame and the app differ. The frame isn't corrected, since this run never saves the .pen.
- **To reverse:** Adding WNBA or MLS would need new MMTVL catalog data first (`TeamCatalog.swift`), then the golden file regenerated.

### D2. Team matching reads a short-lived copy of the guide
- **Step:** 18. **Decision (Recommended):** For each match, run only while a team is picked, the background task copies the guide's programmes, matches them, and lets the copy go. A DEBUG timing line measures the copy.
- **Why:** Step 17 ruled that all matching stays in the background task. The alternative, asking the guide screen channel by channel, moves the same data, does it in many small round trips, and ties the task to the guide screen.
- **Explained:** Every 5 minutes with a team picked, the Roku briefly holds a second copy of the guide: up to 25,000 programmes on a Low Roku, 60,000 on a High one. With no team picked, it never does.
- **Pros:**
  - Simple, and matching never runs on the screen-drawing thread.
  - Costs nothing for people who don't use My Teams.
- **Cons:**
  - A memory peak, and a possible brief UI stall, every 5 minutes on a Streaming Stick. Unmeasured until a Roku runs it.
- **Fallback if a device shows stalls:** read the guide once per guide load, keep only the programmes that name any team, and match against that small set (step 22).

### D3. The team catalog loads at launch only for people who picked teams
- **Step:** 18. **Decision (Recommended):** When teams are picked, the catalogs are read and the team index is built at launch. With no teams picked, they load when first needed: the channel menu, Choose Teams, Settings, or a first pick.
- **Why:** Step 17 asked for the index at launch. qa-deep found that a fully lazy load makes the first channel menu slow to show its team rows. Building it at launch for everyone would cost about 400 KB of memory for people who never use My Teams.
- **Explained:** People who use My Teams get it ready at once. Everyone else pays nothing until they open it.
- **Pros:**
  - Fast for users of My Teams.
  - Free for everyone else.
- **Cons:**
  - The first open of Choose Teams on a Roku with no picks still waits a moment, showing "Loading teams…".

### D4. The Channels footer waits for step 20
- **Step:** 18. **Decision (Recommended):** The Settings footer stays "To favorite or hide one channel: in the guide, press * on it." The frame's "favorite, hide or match" comes when Match Guide exists, in step 20.
- **Why:** The footer would otherwise mention a feature that isn't built yet. Step 13 had already decided this.
- **Pros:** The text is always true.
- **Cons:** None worth noting.

### D5. An upcoming game shows as one line in the guide
- **Step:** 18. **Decision (Recommended):** An upcoming game row is one cell, "Sun 1:00 PM · <game>". MMTVL uses a two-line cell with a calendar symbol.
- **Why:** Roku's TimeGrid draws one title per cell, so a two-line cell would need a custom grid.
- **Pros:**
  - The native grid stays fast on sticks.
- **Cons:**
  - It looks less like MMTVL. Step 22's layout pass may revisit it.

### D6. Wording the frames don't show
- **Step:** 18. **Decision (Recommended):** Where no frame exists, the text follows MMTVL's wording:
  - Settings → My Teams: its sections, the switch descriptions, "Select a team to add or remove it." and "Spelled-out names, such as Louisiana-Monroe or Brigham Young, always count."
  - Picker hints in the frame's style: "OK: open · Back: close", "OK: open · Back: leagues", "OK: add or remove · Back: leagues".
  - "Loading teams…" while the catalog loads. This one is new: MMTVL never waits for its catalog.
- **Pros:** Consistent with the Mac app and with the frames' own hints.
- **Cons:** Unreviewed by the user; easy to change in `SettingsPages.bs` and `TeamPicker.bs`.
- **Added in QA fixes:** "Teams couldn't be loaded" shows when the bundled catalog can't be read. MMTVL silently has no college teams in that case. The next open of Choose Teams or Settings tries again.

### D7. Search's programmes use a title index, built once per guide load
- **Step:** 19. **Decision (Recommended):** A new `SearchTask` (one for the app's life, made when Search first opens) builds a compact title index from the guide the first time Search needs it after each guide load. The guide copy it reads for that is let go at once; every query runs against the index. A new guide drops the index straight away, and the next Search builds it again. DEBUG builds log the build ("Indexed N programmes (T titles) in X ms (guide read Y ms)") and each query ("Found C channels, P programmes in X ms").
- **Why:** Matching every keystroke against a full guide copy would mean one copy per keystroke, or holding a second full copy. MMTVL asks SQLite; the Roku has no database, so the index stands in for it.
- **Explained:** The index holds only what search needs: each folded title once (a show that airs 20 times is stored once), and under it, for each airing, the guide channel, the start and the stop. Programmes that have already ended are left out. Titles and subtitles for the 40 results are then fetched from the guide screen, which already keeps the guide, in one call per answer.
- **Pros:**
  - The guide is copied once per guide load, and only by people who search.
  - Queries scan unique titles, not every airing.
  - Search stays out of TeamsTask's queue, so a long index build never delays My Teams.
- **Cons:**
  - The index stays in memory until the next guide load, even after Search closes. Its size is unmeasured (no Roku yet).
  - The first Search after each guide load waits for the build (the "Searching…" text shows meanwhile).
- **Fallback if a device shows memory pressure:** drop the index when Search closes, on Low Rokus or everywhere (one request kind in `SearchTask`).
- **To reverse:** Build the index inside TeamsTask instead, sharing its guide read with the My Teams match.
- **Orchestrator, on the implementer's question "drop the index when Search closes on Low Rokus?":** No. It's kept until the next guide load, so reopening Search is instant. Step 22's memory alerts (`roAppMemoryNotificationEvent`) drop it together with the logos. That handles the real risk only when the Roku actually runs short, rather than costing a rebuild on every reopen.

### D8. Team results come from TeamsTask, which already holds the catalog
- **Step:** 19. **Decision (Recommended):** TeamsTask gains a `search` request. It ranks teams with `LiveSearch.teamsMatching` over search entries it makes once from the catalogs it already holds. A search waiting during a My Teams match is answered between programmes, as the channel menu's request is. Opening Search sends an empty search, so the entries are ready by the second letter.
- **Why:** The college catalog is 382 KB. A second copy in `SearchTask` would double that memory for no gain.
- **Explained:** One query goes to two Tasks: `SearchTask` answers channels and programmes, TeamsTask answers teams. Each answer carries the query's serial, and an answer to an older text is dropped.
- **Pros:**
  - One copy of the catalog.
  - The team ranking runs off the render thread.
- **Cons:**
  - Two answers per query, so the teams and the programmes can arrive a moment apart.
  - With no team picked, the first Search reads the catalog (as D3).

### D9. The debounce is a Timer in the Search screen; all results come after it
- **Step:** 19. **Decision (Recommended):** `SearchView` waits 0.3 s (`Theme` timing `searchDebounce`) after the last change to the text, then sends the query to both Tasks. Until the answers arrive, the results already on screen narrow at once (channels by name, teams by their search text, programmes by title). Below two characters everything clears at once.
- **Why:** In MMTVL, channels and teams come at once and only programmes are debounced. On a Roku, channels and teams would have to be searched on the render thread to come at once. On a stick that could drop key presses, which is what step 19's done-when checks.
- **Explained:** Typing feels the same as on the Mac: results narrow while you type, and new matches arrive after a short pause.
- **Pros:**
  - No search work on the render thread except narrowing at most 60 results.
- **Cons:**
  - A newly matching channel or team appears about 0.3 s later than on the Mac.

### D10. Search opens only from the guide's Search row
- **Step:** 19. **Decision (Recommended):** Search opens from the guide's Search row, as step 19 says, and only there. MMTVL also opens it over the player and Multiview, but only when phone text arrives; the Roku has no phone remote and no Multiview.
- **Explained:** Back on the keyboard closes Search and returns to the Search row. Back never leaves Live TV. The 3-minute idle return closes Search like the channel menu and Choose Teams.
- **Pros:** Exactly the plan's scope.
- **Cons:** No quick way to search from full screen. Typing from the Roku mobile app's keyboard (ECP `Lit_` keys) isn't handled.
- **To reverse:** A player key (none is free under L4) or ECP text input would open `SearchView` over the player.
- **Orchestrator, on the implementer's question "also from full screen?":** No. L4 leaves no free player key, and the plan scopes Search to the guide. From full screen it's Back → guide → Left → Search, three presses.

### D11. Search follows the frame's layout, with MMTVL's wording where the frame shows none
- **Step:** 19. **Decision (Recommended):** Frame rucDX supplies the layout: the keyboard on the left; on the right, section headers CHANNELS, TEAMS and PROGRAMMES, two-line rows and the check mark. The texts come from MMTVL (as D6):
  - **Channel:** the name, then "<number> · <group>". The frame also shows the programme on now, which would need a guide lookup per row, so it's left out.
  - **Team:** MMTVL's pick title ("Duke Blue Devils (Basketball)", which the 4 Duke teams need to be told apart), then its conference, or the league for a pro team. A picked team adds " · In My Teams" and the check; the focused team, if not picked, adds " · Add to My Teams", as the frame does.
  - **Programme:** the title, then "<number> <channel> · On Now | 9:00 PM | Tue 9:00 PM", then the subtitle or episode if there is one. MMTVL puts the time and channel in the title line; the frame puts them in the detail, and says "Now" where MMTVL says "On Now".
  - **Six rows show at a time** (MMTVL shows eight); with three headers, eight don't fit the frame's results area. Rewind and Fast Forward page by six.
  - **Texts the frame doesn't draw:** MMTVL's "Type a channel, team or show", "No channels or programmes match" and the keyboard placeholder "Channels, teams, shows". New: "Searching…" while a query runs and nothing is shown yet.
  - **Hints:** MMTVL's, with OK for Select: "OK: type · Play: delete · Right: results · Back: close search", "OK: watch · Left: keyboard · Back: keyboard", and "OK: add to My Teams · Left: keyboard" or "OK: remove from My Teams · Left: keyboard". The frame's single hint ("OK on a team: add or remove from My Teams · Back: guide") isn't used.
- **Pros:** The same words as the Mac app, in the Roku design's layout.
- **Cons:** Unreviewed by the user. All of it is in `LiveSearch.rowText`, `message` and `hint`.

### D12. Programme titles match ignoring accents too
- **Step:** 19. **Decision (Recommended):** A programme matches when its folded title (case and accents removed, as MMTVL folds channel names) contains every typed word.
- **Why:** MMTVL's programme query is SQLite `LIKE`, which ignores case for ASCII letters only. "futbol" finds the channel "Telemundo Fútbol" there, but not a programme titled "Fútbol". The Roku's keyboard has no accented letters, so the folded match is the useful one.
- **Pros:** Accented titles can be found with the Roku keyboard.
- **Cons:** A few more programme results than the Mac gives for accented titles.

### D13. Match Guide rematches with a guide run that downloads nothing
- **Step:** 20. **Decision (Recommended):** A choice saves the overrides, then asks `GuideRuns` for a **rematch** (`overridesChanged`). The next guide run reads every guide from the files already in `cachefs:` (`GuideTask`'s `cachedOnly`) and matches again, exactly as a launch run would, with the overrides just saved. It downloads nothing: a guide that is due is read from its old file, and its real download time goes back to the scene, so the run that follows (started at once: `pending` stays set) downloads it. When no run has read the current guides yet ("first", "sources"), the normal run does both. A run already going: the rematch waits for it, like every other request. Refresh Now covers it.
- **Why:** On the Roku, a guide run keeps only the winning channels' programmes (the plan's data flow), so a newly chosen guide channel usually has no programmes held. The pass-1 data alone can't give them; the guide file has to be read again. MMTVL does the same in that case (`setGuideMatch` re-imports the guide when its programmes weren't kept). A partial pass (only the one channel) would need a second way to build and merge the guide data, with its own caps and its own copy of the programmes; a whole run gives the fresh-match result by construction (`MatchGuideTests.theRematchLeavesTheGuideDataAsAFreshMatch`).
- **Explained:** After you pick a match, the guide shows the old match until the run answers, then the new one, everywhere at once: the grid, the banner, My Teams, Search and Settings' counts.
- **Memory on a Low Roku:** the same peak as the 12-hour refresh, which the memory guard already allows for: while the run reads, the old guide data (the holder's field and the guide screen's copy, at most 25,000 programmes) stays, and the run builds its own (at most 25,000); a `.gz` guide is inflated again into `cachefs:` (RAM outside the app's limit, deleted after the run). When it answers, the old holder goes.
- **Pros:** No new data path: one code path for matching; no download.
- **Cons:** A rematch reads and inflates every guide again: seconds on the fixtures, **unmeasured** for US2 (77 MB of XML) on a stick, where it could take minutes. Meanwhile the old match shows.
- **To reverse:** A partial run: scan only the chosen guide for the one EPG id and merge it into a copy of the guide data (costs a second full copy while merging, and a second set of caps to keep equal to a fresh run's).

### D14. Match Guide's data has its own small field; the guide data loses the channel lists
- **Step:** 20. **Decision (Recommended):** `GuideTask` sets a second field, `matchData` (`GuideFetch.matchData`: the matches and each guide's channel list, no programmes). `MatchGuideTask` reads it per open. The channel lists, which only Match Guide reads, are no longer in `guideData` (step 9 put them there "for Match Guide").
- **Why:** Reading a node field copies its whole value. Reading `guideData` would copy every programme for each Match Guide open; the channel lists in `guideData` were also copied into every reader (the guide screen, TeamsTask, SearchTask) that never used them.
- **Explained:** Names are held once (in `matchData`) instead of in every copy of the guide data. For US2 (769 channels) that's a few hundred KB; for a 27,000-channel guide, a few MB.
- **Pros:** Less memory overall; a Match Guide open copies names only.
- **Cons:** One more field on the holder.

### D15. Match Guide ranks in its own Task; MMTVL's 30 suggestions
- **Step:** 20. **Decision (Recommended):** A new `MatchGuideTask` (`components/guide/MatchGuideTask.*`, one for the app's life, made when Match Guide first opens; the newest request wins) runs `EPGSuggester.rank` and `MatchGuide.options`. The plan named `components/guide/MatchGuide.*`; the view is the channel menu's (D16), so the new component is this Task. Like MMTVL (`EPGSuggester.suggest` is `@concurrent`), nothing ranks on the render thread. As MMTVL, the channel menu closes and Match Guide opens when its options arrive; nothing shows meanwhile. The answer is dropped when anything opened meanwhile (a menu, Choose Teams, Search, Settings, the keyboard, the import, the notice), the screen changed, or a newer Match Guide was asked for; the 3-minute idle return cancels it too (MMTVL's `idleCancelsAMatchGuideStillLoading`). Antenna channels will get the antenna guide's suggestions first in step 21 (MMTVL M7j L12); there's no antenna guide yet.
- **Pros:** No stall on a stick, even with a big guide. **Cons:** One more Task thread while it runs.
- **Debug line:** "Match Guide: N candidates from G guide(s) in X ms" (DEBUG builds only; counts and times).

### D16. Match Guide uses the channel menu's look, MMTVL's wording and the frame's row title
- **Step:** 20. **Decision (Recommended):** The design has no Match Guide frame (checked read-only in `design/roku-live-tv.pen`: only the channel menu frame Z3UnCj draws a "Match Guide…" row). Match Guide is drawn by `ChannelMenuView` with `liveMenuWideWidth` (1044, MMTVL's wide menu) and MMTVL's texts:
  - **Title** "Guide for <channel name>"; no programme line.
  - **Rows** Automatic, No Guide, then the current match and up to 30 suggestions, each with its display-name and, on the right, the guide's short label (the file name without `.xml`/`.gz`, else the host: `URLDisplay.guideShortLabel`, MMTVL's `shortLabel`), plus " · Selected" on the chosen one or " · Automatic" on the current match when the choice is Automatic. Automatic or No Guide shows "Selected" when chosen. Focus starts on the selected row.
  - **Channel menu row:** the frame's title "Match Guide…", where MMTVL puts it (after the team rows, before Hide Channel), with MMTVL's value on the right (the matched guide's label, else "None"). The frame draws no value; MMTVL shows one.
  - **Hint:** the channel menu's "Back: close"; Back (and `*`) go back to the channel menu, focused on Match Guide… (D49, M7m L3).
  - **Refused save:** the message shows under the title in `warningText`, wrapped to three lines, and Match Guide stays open (D17).
- **Pros:** No new component to design; the same words as the Mac. **Cons:** Unreviewed by the user; the "·" glyph and wrapped note are device checks.
- **To reverse:** Drop the row value (`ChannelMenu.items`' `matchValue`) to match the frame exactly.

### D17. A refused save keeps Match Guide open with its message; at most 500 matches
- **Step:** 20. **Decision (Recommended):** L5's refusal (under 4 KB free, or the save too large for what's left) shows `SettingsStore`'s message in the open Match Guide menu, and nothing changes. New: when the choice would make more than 500 overrides (the store's limit, which would otherwise drop one of them silently on save), the save is refused with "This Roku keeps at most 500 guide matches, so this one wasn't saved. Set some channels back to Automatic and try again." Choosing Automatic is never refused for the count, since it only removes keys.
- **Why:** MMTVL has no such limits (it only logs a failed save); L5 asks for a message rather than a silent failure.
- **Pros:** Every failed choice says why. **Cons:** New text, unreviewed.

### D18. Orchestrator answers to step 20's two questions
- **Step:** 20. **Decision (Recommended):**
  - (a) Keep D13's full re-read on a rematch.
  - (b) Keep the channel menu's Match Guide row value (the guide's label, else "None"), which MMTVL shows and the approved frame doesn't draw.
- **Why (a):** A rematch must give exactly what a fresh match gives, or a channel could show a different guide after the next refresh than right after the choice. Its memory peak is the same as the 12-hour refresh, which the guide's memory guard already covers. Only its time on a stick is unknown.
- **Why (b):** Parity with MMTVL. It tells the user, before opening the submenu, whether a channel has a guide and which one.
- **Explained:** (a) Choosing a guide re-reads the cached guide files, possibly a few seconds on a stick, without downloading anything. (b) The menu row reads, for example, "Match Guide…   guide.xml".
- **Pros:**
  - (a) Always correct, and no second code path to keep in step.
  - (b) Same as the Mac app.
- **Cons:**
  - (a) Slow on big guides on a Stick, unmeasured. The partial-scan alternative, re-reading only the affected channel, would be faster but could drift from a full match.
  - (b) Differs from the frame.
- **To reverse:** (a) A partial scan in `GuidePipeline` for one channel, if step 23 shows a rematch takes too long. (b) Drop `value` in `ChannelMenu.bs`.

### D19. The scene keeps `Unicode.bs` for Match Guide; SearchView's imports go to step 22
- **Step:** 20. **Decision (Recommended):** MainScene loads `Unicode.bs` (about 10 KB compiled, with no tables kept between calls) and `MatchGuide.bs`, so it can lowercase override keys exactly as MMTVL does when a choice is saved.
- **Why:** qa-deep measured the cost as about 10 KB of code and a few microseconds per choice. Moving the lowercasing into a Task would need a second copy of the overrides, plus a way to handle an import made between opening Match Guide and choosing.
- **Explained:**
  - The fold tables that matter for memory are in `EPGMatcher.bs`, which the scene doesn't load.
  - qa-deep also found that SearchView, which is on the screen-drawing thread too, loads `EPGMatcher.bs` and `LiveSearch.bs`: about 153 KB compiled. That is a bigger target.
  - Step 22 (the low-end pass) will measure it and either move SearchView's narrowing to SearchTask or slim its imports.
- **Pros:** No extra copies and no stale-snapshot path; exact parity.
- **Cons:** About 10 KB more code on the render thread.

### D20. An empty guide label reads "Selected", not " · Selected"
- **Step:** 20. **Decision (Recommended):** When a Match Guide candidate's guide has gone, which leaves an empty label, its value reads "Selected". MMTVL shows " · Selected" with a stray leading dot.
- **Why:** It's a small cosmetic glitch in MMTVL; copying it adds nothing.
- **Pros:** Cleaner text.
- **Cons:** A one-character difference from the Mac app, only in a rare state.


### D21. Switch `discoverByBroadcast` (on): find tuners with SiliconDust's UDP broadcast
- **Step:** 21 (U1). **Decision (Recommended):** `AntennaConfig.discoverByBroadcast = true`. `roDataGramSocket` sends MMTVL's discover packet (`HDHomeRun.discoverRequestHex`, CRC-32 by `roByteArray.GetCRC32`) to 255.255.255.255 and each of the Roku's private /24 broadcasts on UDP 65001, twice 300 ms apart, and reads replies for 1.5 s (at most 256 read, 64 kept, 4 per address). A reply counts only from a private address on one of the Roku's /24s that isn't its own, naming a BaseURL that is exactly that address; `discover.json` is then asked at `http://<that address>/discover.json`, and its answer must agree (same DeviceID, BaseURL the origin, LineupURL on it, 1–16 tuners) and, when the transfer reports the address it reached, come from that address.
- **Why:** Probe f's first method, and MMTVL's own (M7j L4). It's the only method that finds more than one tuner.
- **Explained:** A Roku reports no netmask, so "the subnet" is the /24 of each of its addresses (probe f's choice). A LAN with a wider mask and the tuner outside the Roku's /24 needs the typed address.
- **Pros:** Finds every tuner without setup. **Cons:** Whether a Roku sends broadcasts at all is unverified (probe f).
- **To reverse:** Set it to `false` in `roku/source/lib/AntennaConfig.bs`.

### D22. Switch `discoverByName` (on): `hdhomerun.local` when the broadcast finds nothing
- **Step:** 21 (U1). **Decision (Recommended):** `AntennaConfig.discoverByName = true`: `http://hdhomerun.local/discover.json` through `roUrlTransfer` (Roku resolves the name), only when the broadcast found nothing. Its BaseURL must be a private address on the Roku's /24, and the device is used by that address from then on.
- **Why:** Probe f's second method, and MMTVL's fallback.
- **Pros:** Works where broadcasts don't. **Cons:** One tuner at most; whether Roku resolves `.local` names is unverified.
- **To reverse:** `false` in `AntennaConfig.bs`.

### D23. Switch `nameNeedsPeer` (on): `hdhomerun.local` counts only with the reported address
- **Step:** 21. **Decision (Recommended):** `AntennaConfig.nameNeedsPeer = true`: the `hdhomerun.local` answer counts only when `roUrlEvent.GetTargetIpAddress` reported the address the transfer reached and it is the BaseURL's address. A reported address that differs is refused even with the switch off.
- **Why:** MMTVL never trusts a name: it resolves `hdhomerun.local` itself and asks by IP (security M2). A Roku can't resolve a name without fetching, so the reported peer is the only way to know the answer came from the address it names. Whether a Roku reports it, and for which hop, is step 8's open device check.
- **Explained:** If a Roku never reports the peer, `hdhomerun.local` never works with this on; the typed address still does.
- **Pros:** No name-based trust. **Cons:** Possibly dead on Rokus that don't report the peer.
- **To reverse:** `false`: a BaseURL that is a private address on the Roku's /24 is enough.

### D24. Switch `playRawTS` (on): antenna channels play the tuner's raw MPEG-TS
- **Step:** 21 (U1). **Decision (Recommended):** `AntennaConfig.playRawTS = true`: the lineup's `http://<tuner>:5004/auto/v<n>` goes straight to the `Video` node (no prefetch, no warming, no logo fetch: every GET takes a tuner). Off: antenna channels still list, and playing one shows "This Roku can't play antenna channels".
- **Why:** Probe b decides whether raw TS plays at all (Roku staff said in 2014 it isn't a supported container). Building the path means only the switch changes.
- **Pros:** Ready for the probe. **Cons:** May not play on any Roku; then this is the switch to turn off.
- **To reverse:** `false` in `AntennaConfig.bs`.

### D25. Switch `streamFormat` (""): the Video node's format for antenna streams
- **Step:** 21 (U1). **Decision (Recommended):** `AntennaConfig.streamFormat = ""` leaves `streamFormat` unset, so Roku picks from the stream (the tuner sends `video/mpeg`). Probe b tries `hls`, `mp4`, `mkv` and unset; whichever plays goes here. Playlist channels keep `hls`.
- **Why:** None of Roku's documented formats is raw TS; unset is the only one that lets the player sniff the container.
- **Pros:** One constant to change. **Cons:** A guess until probe b runs.
- **To reverse:** Set the format probe b found.

### D26. Switch `playMPEG2` (on): MPEG-2 channels only where the Roku decodes MPEG-2
- **Step:** 21 (U1). **Decision (User, U1; switch Recommended):** `AntennaConfig.playMPEG2 = true`: H.264 always; MPEG-2 (`VideoCodec` "MPEG2") only where `Capabilities` reports `mpeg2` (`CanDecodeVideo`). Elsewhere those channels are hidden from the lineup, counted, and Settings → Device's Antenna MPEG-2 Channels row says "Some antenna channels need MPEG-2, which this Roku can't play" (Settings → Antenna's footer too). A later tuner's H.264 copy of a hidden number still plays. An entry naming no codec is listed (it may be either). Such a channel carries `codecUnknown`, and on a Roku without MPEG-2 its "No signal" or "Can't play" failure says "This channel may need MPEG-2, which this Roku can't play" instead (D40). Off: H.264 only on every Roku ("Off: H.264 Only" on Device).
- **Why:** U1. ATSC 1.0 is mostly MPEG-2, so on most Rokus few antenna channels will show; the row explains why.
- **Pros:** No channel that can't play is listed (where the lineup says the codec). **Cons:** An unlabelled MPEG-2 channel is listed and fails on a Roku without MPEG-2 (with D40's hint).
- **To reverse:** `false` for H.264 only; or hide unlabelled codecs too (`AntennaLineup.isMPEG2`).

### D27. Switch `guideFormat` ("xmltv"): SiliconDust's XMLTV, read by GuideTask
- **Step:** 21 (U1). **Decision (Recommended):** `AntennaConfig.guideFormat = "xmltv"`: `https://api.hdhomerun.com/api/xmltv?DeviceAuth=…` downloaded by AntennaTask into `cachefs:/antenna/guide.data`, then read by GuideTask's pipeline after the other guides, for antenna channels only (GuidePipeline's `antenna` request), and inflated there if it comes as a gzip body where inflate is kept. `"json"` (unverified) pages `https://api.hdhomerun.com/api/guide.php?DeviceAuth=…&Start=<s>` (at most 12 pages, 4 MB and 30 s each) and writes them out as XMLTV (`AntennaGuide.jsonToXMLTV`: a channel per GuideNumber with the number, name and affiliate as display-names; title, sub-title, desc, category, onscreen episode), so the same pipeline reads it.
- **Why:** MMTVL uses the XMLTV (7.2 MB for 2 days). The JSON shape is the one SiliconDust's apps are reported to use; nobody has checked it here (no request to SiliconDust from this Mac).
- **Explained:** GuideTask never sees DeviceAuth or the URL: it only reads the file.
- **Pros:** One pipeline for both; matching by GuideNumber either way. **Cons:** The JSON path is untested against the real service, and its window length per page is a guess.
- **To reverse:** `"json"` if the XMLTV is too big for a stick.

### D28. Switch `guideHTTPGzip` (off): no HTTP gzip decoding on the guide download
- **Step:** 21. **Decision (Recommended):** `AntennaConfig.guideHTTPGzip = false`: `EnableEncodings` stays off, as GuideTask's (step 9), so no `Accept-Encoding: gzip` is sent and the server sends the plain XML; if it sends a gzip body anyway, GuidePipeline inflates it (where inflate is kept, under the run's limits).
- **Why:** Step 9 kept `EnableEncodings` off because roUrlTransfer would inflate natively into cachefs: faster than the size polls can stop it (a gzip bomb bounded only by the poll). SiliconDust's host is fixed and https, but the same rule holds.
- **Pros:** The 64 MB cap holds on the bytes written. **Cons:** About 7 MB on the wire instead of about 1 MB.
- **To reverse:** `true`, if step 23 shows the plain download too slow.

### D29. The typed address: an IPv4 literal on the LAN, kept in settings, never shown
- **Step:** 21. **Decision (Recommended):** Settings → Antenna → Address… opens the keyboard (empty: the saved address is never shown; the row says "Set" or "None"). OK with nothing typed forgets it. It's accepted only as a private (10/8, 172.16/12, 192.168/16) or link-local IPv4 literal, written plainly, not the Roku's own and not .0 or .255 (`SettingsEdits.checkTunerAddress`); names, public and loopback addresses are refused with "Type the tuner's IP address on your network, like 192.168.1.20". It's saved as `settings.antennaAddress` (Roku-only, kept by an import) and checked again by the task (`HDHomeRun.typedHost`; a test checks the two agree). It's always tried after the other methods (de-duplicated by DeviceID), so a tuner on another subnet works. Its row says "No tuner answered at that address" or "That address isn't an HDHomeRun tuner".
- **Why:** The plan's "LAN addresses only" and L6's "never show a tuner address". A name would need the same peer check as `hdhomerun.local`.
- **Pros:** Works where discovery can't. **Cons:** A DHCP change breaks it (the README's DHCP reservation advice applies).
- **To reverse:** Allow `.local` names with D23's peer rule.

### D30. Diagnosis on the Roku: MMTVL's order, plus 805 and the error's numbers
- **Step:** 21. **Decision (Recommended):** A failed antenna stream (a Video error or a stall) starts a diagnose AntennaTask: `status.json` (every tuner busy → "Both antenna tuners are in use"; unanswered → "The antenna tuner isn't answering"), then `lineup_status.json` (a scan → "The tuner is scanning for channels"), then the stream's status: 404 → "This channel is no longer on the tuner", 503 or none → "No signal on this channel", else "Can't play this channel". The Roku adds `X-HDHomeRun-Error` 805 after the scan check. The status and 805 are read from the Video node's error texts (`errorMsg`, `errorStr`, `errorInfo`) by `PlayerSession.errorNumbers`, which passes on only the numbers (the texts may hold the stream URL). Unreachable and not-on-the-tuner search again (or read the lineup again) and play the channel once more, as MMTVL. The app's own stream count (`PlayerSession.tunerBudgetProblem`) is MMTVL's rule, called with no other streams: the Roku has one Video, which the channel replaces.
- **Why:** MMTVL L8, L9. Whether a Roku's error text shows the HTTP status or the 805 header is unverified, so the tuner's own state decides first, as in MMTVL.
- **Pros:** MMTVL's messages. **Cons:** "No signal" is the fallback when the Roku says nothing useful.
- **To reverse:** Drop the 805 rule in `HDHomeRun.problemFor`.

### D31. Discovery and lineups on the playlist's cadence; a tuner missing once keeps its channels
- **Step:** 21. **Decision (Recommended):** AntennaTask runs at launch, on the 15-minute tick and when the guide opens (when the last run is 10 minutes old), on Refresh Now, Find Tuners, a typed address and a setting change. No tuner answering keeps the channels once (a tuner rebooting); twice in a row they go. The launch target waits for both the playlist's and the antenna's first **lineup** answer (D36: never for SiliconDust's download; the lineup watchdog gives one after 90 s), and for the merge that answer starts (D37). Live TV works with a tuner and no playlist (Settings counts a found tuner as set up, as MMTVL).
- **Why:** The plan ("on the playlist's cadence"); MMTVL's `hasLiveSource`. Without the wait a last antenna channel couldn't open at launch.
- **Pros:** A last antenna channel plays at launch. **Cons:** With the antenna on and no tuner, the launch waits for the search: about 3.5 s (the 1.5 s broadcast, then `hdhomerun.local`'s 2 s timeout; corrected after QA). The 2 s timeout stays (D39).
- **To reverse:** Drop the wait in `resolveLaunch`.

### D32. The antenna guide's schedule and files, and no guide run while it downloads
- **Step:** 21. **Decision (Recommended):** SiliconDust's guide is downloaded inside an AntennaTask refresh, only when Guide from SiliconDust is on, the refresh found channels, and `AntennaGuide.downloadStep` says so: 20–28 h (random) after a success, an hour after a failure, never within an hour of the last download or attempt (Refresh Now too), and at once when the file is gone (cachefs: is emptied by a reboot). The files are in `cachefs:/antenna/` (`guide.data`, `.part`, `.time`, `.due`, `.attempt`; no token in a name), outside the folder GuideTask prunes. The scene asks for the guide only when no guide run is alive, and holds guide runs while that refresh runs (GuideRuns' pending), so no run reads a half-written file. A new antenna guide, a changed antenna channel set or a switch change starts a rematch (GuideRuns' rematch: nothing downloaded again). Turning the guide (or the antenna) off forgets the due time, so turning it on downloads it (the hour's limit still holds), as MMTVL. Settings → Antenna's Status: "N programmes · M of K channels · Updated 6:12 PM", "Failed: <why>", "Not loaded yet", "Off".
- **Why:** MMTVL L10, L11, security L1. The files follow L5 (guides live in cachefs: only).
- **Pros:** At most daily, no token stored. **Cons:** Antenna refreshes with the guide on delay a guide run by a few seconds. (After QA and security L-1, a task the watchdog or a setting gave up on keeps the file gated while it's alive: D38.)
- **To reverse:** A separate guide task with its own schedule.

### D33. Settings → Antenna: MMTVL's wording, no scan and no Channels page
- **Step:** 21. **Decision (Recommended):** The design has only frame wjg72's Antenna row ("1 Tuner · 12 Channels"); there's no Antenna page frame, so MMTVL's page and wording: Antenna (Use Antenna), Tuners (each tuner: name, "2 tuners", "<model> · N channels"; Find Tuners with "Found 1 tuner" / "Searching…" / "No HDHomeRun found on this network"; Address…), Guide (Guide from SiliconDust; Status). The Tuners footer says channels come from the tuner's lineup and to scan on the tuner's own page or in MMTVL, plus the protected and MPEG-2 counts. No Scan for Channels (the plan) and no per-channel Channels page (single channels are hidden from the guide's channel menu, as playlist ones). With nothing set up and the antenna off, Live TV shows the Antenna row alone; on with no tuner yet, the Channels section; with a tuner, the Guides, Channels and Refresh Now ("Reads the tuner's channels and downloads the guides again now.").
- **Pros:** The Mac's words. **Cons:** Unreviewed by the user; no frame.
- **To reverse:** Draw a frame and follow it.

### D34. No Swift golden for the antenna
- **Step:** 21. **Decision (Recommended):** The antenna's parity is the Swift tests mirrored case for case (AntennaLineupTests 19/19, AntennaDiagnosisTests 8/8, AntennaGuideTests 11/11), not a `RokuParityTests` golden.
- **Why:** The brief asked for goldens "where it's cheap". The Swift cases are small hand-built inputs with exact expectations, so mirroring them gives the same contract without new MMTVLTests code and a full Swift run; the rules are short (no fold tables or ranking with floating-point ties, which is where steps 9 and 20 needed goldens).
- **Pros:** No MMTVLTests change. **Cons:** A later change to MMTVL's antenna rules isn't caught by a Roku test.
- **To reverse:** Add an `antenna.golden.json` written by `RokuParityTests` from the same inputs.

### D35. A failed antenna channel's retry replays in place
- **Step:** 21 (QA major 1). **Decision (Recommended):** After the search or lineup read a diagnosis asked for, the channel is played again on the player where it is, full screen or in the guide's preview, with the antenna part's fresh copy (a moved tuner's new address). The screen never changes (`PlayerSession.retryAction`, whose `screen` is always ""). Only when it still fails, is still the current channel and the lineup still has it. Once per choice, as MMTVL.
- **Why:** MMTVL's `diagnose` retries on the same player and never moves the user. The first build called `playChannel`, which opened the player over the guide or Settings when the task answered.
- **Pros:** No surprise screen change. **Cons:** A retry under Settings plays unseen until Settings closes.
- **To reverse:** Retry only while `m.screen = "player"`.

### D36. The lineup answers before SiliconDust's download
- **Step:** 21 (QA major 3). **Decision (Recommended):** A refresh sets `lineupResult` (discovery, lineups, channels, keys) before anything is downloaded, then `result` with the guide's outcome (`AntennaLineup.refreshRun`, tested in lib). The launch waits only for the lineup answer; guide runs still wait for the download (D32). The watchdog is 90 s for the lineup, then the download's own (D38).
- **Why:** The first build answered once, after the download: up to 180 s at launch after any reboot (cachefs: empty).
- **Pros:** The launch waits about as long as discovery. **Cons:** Two fields per run.
- **To reverse:** A separate follow-up guide request.

### D37. The antenna's channels merge off the render thread, on two keys
- **Step:** 21 (QA majors 2 and 4). **Decision (Recommended):** PlaylistTask merges: each playlist load gets the antenna part (`Lineup.mergeParts`: the playlist's channels, then the antenna's numbered after them) and builds the lineup, fields and key over both. A new antenna part starts a **merge-only** PlaylistTask over the scene's current lists (`Lineup.playlistPart` takes the playlist's part back out). The scene only assigns. Only an emptied playlist (Change Playlist URL, Remove Live TV Source) is merged on the render thread, antenna-sized work only. The task's `AntennaLineup.setKeys` gives two SHA-1 keys, never logged: `matchKey` (id, name, GuideNumber) and `payloadKey` (also each stream URL, tuner count and codec flag). `Lineup.antennaChange`: a new payload merges, and only a new match key rematches the guides. The launch also waits for the merge its lineup answer started.
- **Why:** The first build merged only on the id/name key, so a tuner's new DHCP address never reached the channels, and the retry played the stale URL. It also rebuilt the lineup on the render thread at every playlist refresh once antenna channels existed, which undid step 9's security L-5 and risked Roku's 3 s kill.
- **Pros:** Render-thread work stays assignment-only. **Cons (accepted after QA round 2):** O(n) field copies remain:
  - `task.base` (the merged lists into a merge-only task);
  - its result back;
  - `teamsTask.channels`;
  - QA 4's `rebuildLineup` when the prefs or My Teams changed during a task.
  Timing them for a 10,000-channel playlist on a stick is a device check. Round 2: any task that ends or is given up starts a merge that waited (`Lineup.afterTask`), and a stopped task clears it (`Lineup.afterStop`), so the launch never waits for a merge that won't come.
- **To reverse:** Merge in the scene again, if the device check shows it's cheap.

### D38. Antenna requests that arrive while a task is busy wait; the guide file stays gated
- **Step:** 21 (QA minor 8, security L-1). **Decision (Recommended):**
  - A refresh asked for while one runs (a typed address, Use Antenna or Guide from SiliconDust turned on, Find Tuners, Refresh Now) runs right after it (`m.antennaPending`, carrying Refresh Now's manual).
  - A guide download that can't start because a guide run, or a task given up on, may read or write the file waits (`m.antennaGuidePending`). It starts when that ends (`antennaGuideMayGo`, after a guide run and when an abandoned task stops).
  - An AntennaTask the watchdog or a setting gives up on is kept while alive (`m.abandonedAntennaTask`). Guide runs count it as busy while it asked for the guide, and no new refresh downloads meanwhile (`GuideRuns.antennaBusy`, `antennaMayDownload`, tested).
  - The download's watchdog: 300 s for the XMLTV, 600 s for the JSON guide (above its worst case of about 507 s).
- **Why:** QA found these requests dropped. Security L-1: XMLTVScan reads by path and offset, so a run could read halves of two files.
- **Pros:** No lost request, no torn read. **Cons:** A stuck task holds guide runs until its state reads stop or done.
- **To reverse:** Drop the pending flags; let the watchdog release the gate.

### D39. `hdhomerun.local`'s timeout stays 2 s
- **Step:** 21 (QA minor 11). **Decision (Recommended):** The name probe keeps MMTVL's 2 s (`HDHomeRun.timeoutMs`). D31's text now says about 3.5 s with no tuner.
- **Why:** mDNS answers can take over a second; a shorter timeout could miss a tuner that's there, and the wait is once per launch.
- **Pros:** Finds slow mDNS answers. **Cons:** A 3.5 s launch wait with the antenna on and no tuner.
- **To reverse:** A shorter `timeoutMs` for the name probe in `HDHomeRun.byName`.

### D40. An unlabelled channel on a Roku without MPEG-2: "This channel may need MPEG-2, which this Roku can't play"
- **Step:** 21 (QA minor 10). **Decision (Recommended):** A channel whose lineup entry names no codec carries `codecUnknown`. On a Roku that doesn't play MPEG-2 (Capabilities or D26's switch), its diagnosed "No signal on this channel" or "Can't play this channel" reads "This channel may need MPEG-2, which this Roku can't play". The tuner's own answers (busy, scanning, gone, not answering) still say themselves (`HDHomeRun.problemMessage`'s hint, tested).
- **Why:** D26 lists such channels; without a hint the failure would read as a reception problem. The wording follows Settings → Device's "Some antenna channels need MPEG-2, which this Roku can't play", in MMTVL's sentence style (no full stop, as the other messages).
- **Pros:** Explains the likely cause. **Cons:** It may be wrong for a channel that truly has no signal.
- **To reverse:** Drop the hint argument in `diagnoseStream`.

### D41. A tuner whose lineup can't be read keeps its channels
- **Step:** 21 (QA minor 6). **Decision (Recommended):** A tuner that answered discovery but whose `lineup.json` failed keeps the previous answer's channels on its address (the scene sends them as `previous`; `AntennaLineup.withKept`, tested). A readable lineup's channel always wins. Its row reads "The antenna tuner isn't answering", as MMTVL.
- **Why:** MMTVL's AntennaSource keeps a device's entries when its lineup fails.
- **Pros:** No channels vanish for one bad read. **Cons:** A channel removed from the tuner meanwhile lingers until a lineup reads.
- **To reverse:** Drop `previous` from the request.

### D42. Find Tuners' line, and when Settings says "Searching…"
- **Step:** 21 (QA minor 7). **Decision (Recommended):**
  - Find Tuners' line is set only by its own search: "Found N tuners", "No HDHomeRun found on this network", or (the tuners known before didn't answer, their channels kept once) MMTVL's "No HDHomeRun answered".
  - A later search that finds a different number of tuners clears it.
  - "Searching…" shows only during Find Tuners' search, or while no tuner is known.
  - A no-answer search still updates the tuner list (empty) and the typed address's problem.
- **Why:** The line went stale, and every 15-minute refresh showed "Searching…".
- **Pros:** The line means what it says. **Cons (accepted, QA round 2):** a Find queued behind a running refresh shows "Searching…" during that refresh too.
- **To reverse:** In `applyAntennaLineup` and `antennaSettingsInput`.

### D43. A retry waits for a lineup answer from a run that started after its diagnosis
- **Step:** 21 (QA round 2). **Decision (Recommended):** The diagnosis records `{ id, minSerial }`, where `minSerial` is the serial of the next refresh run (the one it starts, or the one queued after a running refresh). A lineup answer from an older run keeps the retry waiting and doesn't use it up (`PlayerSession.retryAction`'s `keep`). Only the run it asked for, or a later one, retries. Lineup and result answers whose serial isn't the tracked run's are ignored.
- **Why:** A refresh already past its lineup when the diagnosis asked for a search answered with the old address and used up the one retry, before the run that would find the new address started.
- **Pros:** The one retry uses the address the search found. **Cons:** The retry waits for a whole discovery (about 2–4 s).
- **To reverse:** Retry on the next answer, whatever its run.

### D44. A retry while Settings shows waits for Settings to close
- **Step:** 21 (QA round 2; the coordinator's call). **Decision (Recommended):** While `m.screen` is "settings", a due retry stays pending (`retryAction`'s `keep`), and `closeSettings` runs it if the channel is still the current one. In the guide or the player it replays in place, as D35.
- **Why:** A replay behind Settings starts audio nobody asked for.
- **Pros:** No surprise audio. **Cons:** The channel stays failed under Settings until it closes.
- **To reverse:** Drop the "settings" case in `PlayerSession.retryAction`.

### D45. Memory alerts drop logos and Search's index first, and what goes stays gone until the next launch
- **Step:** 22. **Decision (Recommended):** `MemoryRelief.apply` (pure, tested) decides, per alert:
  - **80 % (level 1):** channel logos off (the guide's rows and the banner drop theirs, LogoTask's queue empties) and SearchTask's title index dropped;
  - **85 % (level 2):** also the guide window shrinks (D46);
  - **90 % or more (level 3):** also My Teams stops copying the guide (D48).

  Logos, the window and the My Teams change stay until the app is opened again. The search index is dropped again by every alert from level 1, since the next search builds it again. A fall below a threshold (Roku OS 15.2 alerts both ways) brings nothing back. The saved Channel Logos setting is unchanged; Settings → Device says why they're off (D52).
- **Why:** The plan asks alerts to drop logos and shrink the guide window, and step 19 (D7) handed the index to these alerts. Bringing things back when memory falls would load them again and push memory back up, so a Roku near its limit would cycle.
- **Explained:** On a Roku that runs short once, the guide loses its logos (and, if it gets worse, some hours) for the rest of that session. Opening the app again starts fresh.
- **Pros:**
  - Cheapest, least visible things go first; the index costs only a rebuild.
  - No cycling near the limit.
- **Cons:**
  - A single short spike costs the logos for the whole session.
  - With Search open, a rebuilt index can raise memory again and draw another alert (each one drops it again).
  - QA round 1: a drop that arrives while the index is being built (the build can't stop, D7) is done right after that request. A query already waiting uses the new index once, then it goes, so the index isn't kept after the alert.
  - The levels are Roku's documented thresholds, not measured on a stick (step 23).
- **To reverse:** Change `MemoryRelief.apply`; to bring things back on a fall, act on level 0 in `onMemoryAlert`.

### D46. The guide window shrinks to 12 hours, read again from the files there are
- **Step:** 22. **Decision (Recommended):** At level 2, `MemoryRelief.shrunkGuideHours` (12) becomes the window. GuideTask's new `windowHours` field carries it to every run from then on, and the scene asks for a rematch run at once (GuideRuns' rematch: it downloads nothing and reads the cached files for the shorter window). The antenna guide's download uses the same window.
- **QA round 1:**
  - The shrink's run doesn't wait out the hour after a failed run (`GuideRuns.rematchWaits` with the scene's `shrinkPending`, tested). A Match Guide rematch still waits.
  - Settings → Device shows "12 Hours: Low Memory" only once a run with the 12-hour window has answered (the window of the guide held, `m.guideShownHours`). Until then it shows the class's hours, which is what the guide holds. Of the two options QA gave, this was the simpler, and the page never claims a window the guide doesn't have.
- **Why:** The guide data is the biggest thing the app keeps. Trimming it in place would take a long loop on the render thread; a guide run does the work in a Task with its memory guard.
- **Explained:** The guide shows 12 hours ahead (plus the past 2 hours) instead of 24 or 36.
- **Pros:**
  - Roughly halves the programmes kept.
  - No download, and the work stays off the render thread.
- **Cons:**
  - While the run reads, the old guide is still held, a brief peak at a bad time. GuideTask's memory guard stops reading if memory runs out.
  - One step only (no 6-hour step at 90 %).
  - If the shrink's own run fails, its retry waits out the normal hour (`shrinkPending` clears when a run starts).
- **To reverse:** Change `shrunkGuideHours`, or drop `shrinkGuide` from `MemoryRelief.apply`.

### D47. Alerts are read on the main thread, with Roku's own fallback, and an old Roku OS counts its one alert as level 2
- **Step:** 22. **Decision (Recommended):**
  - `main.bs` creates `roAppMemoryMonitor`, calls `EnableMemoryWarningEvent(true)` on its port and hands each `roAppMemoryNotificationEvent` to the scene's `memoryAlert` field.
  - QA round 1: the monitor and the fallback's `roDeviceInfo` are both kept in the AA Main holds for its whole loop, as Roku's example keeps its object. A released `roDeviceInfo` would send nothing.
  - QA round 1: the scene observes `memoryAlert` with a handler that reads each event's own data (`event.getData()`), not the field's latest value. Two alerts set back to back (a 90 going up, then an 89 going down) are therefore both applied. Of QA's two options, this keeps every alert. Sending only the highest level from main would also work, since drops stay (D45), but it would re-send old alerts.
  - The level reads the higher of the event's `memoryUsagePercent` and `GetMemoryLimitPercent()` at that moment.
  - Where the monitor is missing or its alerts can't be turned on, `roDeviceInfo.EnableLowGeneralMemoryEvent(true)` is used, as Roku's own example does: "low" is level 2, "critical" level 3.
  - With neither, nothing is dropped early, as before.
  - Before Roku OS 15.2 there is one alert, at 80 %, so that alert counts as level 2 (the 85 % one will never come).
  - Every call is guarded.
- **Why:** Roku's docs (rokudev/dev-doc, `roappmemorymonitor.md`, `ifappmemorymonitor.md`, `roappmemorynotificationevent.md`, release notes 15.2). developer.roku.com refused the fetch (403); the same pages in Roku's own GitHub docs repo were read instead.
- **Explained:** Newer Roku OS versions warn at 80, 85, 90 and 95 %; older ones warn once. The app reacts to whichever it gets.
- **Pros:** Works on every Roku OS the app runs on, and never crashes for a missing call.
- **Cons:**
  - **Unverified:** the event's value type, the throttling, and whether a 15.2 Roku really sends the 85–95 % alerts (step 23). The units of `GetChannelMemoryLimit` aren't documented (Capabilities reads them by size).
  - A Roku with no monitor gets only the device's "low", which may come late.
- **To reverse:** In `MemoryRelief.levelOf` and `subscribe`.

### D48. At a critical level, My Teams matches game entries only (D2's cheap fallback)
- **Step:** 22. **Decision (Recommended):** From level 3, the scene's match requests carry `skipGuide: true`, and TeamsTask then makes no copy of the guide. Game entries ("Away @ Home" channels) still match; programmes on networks and upcoming games don't, until the next launch.
- **Why:** D2's 5-minute copy (up to 25,000 programmes on a Low Roku) is a memory peak. Skipping it costs one field and one check, whereas D2's other fallback (a pre-filtered team set per guide load) is new work.
- **Explained:** On a Roku about to run out of memory, My Teams keeps its game channels but stops reading the guide.
- **Pros:** Removes the largest periodic peak exactly when it matters.
- **Cons:** My Teams loses its network games and upcoming games for the rest of the session.
- **To reverse:** Drop `skipGuide` from `requestTeams`, or build D2's pre-filtered set.

### D49. Logos load at their display size; no WebP conversion
- **Step:** 22. **Decision (Recommended):** The guide's channel cell and the banner set the Poster's `loadWidth`/`loadHeight` to the size shown (48 and 96 px), keeping `scaleToFit`. Nothing is converted to WebP. QA round 1: the two fields are set in the XML markup, so they are in place before any `uri` (Roku's Poster doc). Their values are Theme's `guideLogoSize` and `liveBannerLogoSize` written out; no test ties them together, so change both together.
- **Why:**
  - Roku's "Memory management" page: texture memory is width × height × 4 bytes, whatever the file's size or format. LogoCache keeps logos up to 512 KB, which can be a 2000-pixel square (16 MB of texture each).
  - WebP only shrinks files. The app's own bitmaps are 9-patches (PNG by definition) and icons of at most 86 px. The provider's logos arrive in whatever format the provider uses, and LogoCache already keeps `.webp` ones as they are.
  - The plan's logo cache (cachefs, LogoTask) is unchanged.
- **Explained:** A logo now takes at most 48 × 48 × 4 bytes (9 KB) in the guide, whatever its file.
- **Pros:** Bounded texture memory for logos.
- **Cons:** **Unverified:** how a Poster scales a non-square logo with both load fields set (it should keep the aspect ratio). Check with `loaded_textures` on port 8080 (step 23).
- **To reverse:** Remove the two attributes in `GuideChannelCell.xml` and `PlayerBanner.xml`.

### D50. No separate 720p images
- **Step:** 22. **Decision (Recommended):** No HD image set (`uri_resolution_autosub`). An HD Roku scales the FHD bitmaps by 2/3.
- **Why:** Roku recommends 720p images "for performance reasons". Here every bitmap is a 9-patch or icon of at most 86 × 86 px (under 30 KB of texture each), with corners and borders on the 3-px grid. The splash and the app icon already have HD versions in the manifest.
- **Pros:** One image set, with no URI rewriting.
- **Cons:** Corners scaled by 2/3 may be slightly soft at 720p (a device check).
- **To reverse:** Run `gen-ninepatch.py` at 2/3 into `images/hd/`, and add `uri_resolution_autosub` plus `$$RES$$` paths in `Theme.images()`.

### D51. The 720p layout check is a test of the FHD layout
- **Step:** 22. **Decision (Recommended):** `Layout720pTests` checks that:
  - the manifest designs for FHD only (`ui_resolutions=fhd`, so an HD Roku scales by 2/3);
  - every layout value in Theme is a multiple of 3 (counts of rows and lines aside);
  - fonts are at least 24 px;
  - each screen's boxes fit 1920 × 1080: the guide's grid and hint, the group column, Search's results and hint, Choose Teams' columns, Settings' columns, track and band, the menus, the banner and badge.
- **Why:** With auto-scaling, nothing clips at 1280 × 720 that fits 1920 × 1080, and values on the 3-px grid land on whole pixels.
- **Pros:** Runs on every `test:local`; a new value off the grid fails it.
- **Cons:** Text widths in Roku's system font can only be checked on a Roku: long titles, the wide menu's values and the Device rows (step 23).
- **To reverse:** Delete the test.

### D52. Settings → Device texts per class and after memory alerts
- **Step:** 22. **Decision (Recommended):**
  - Channel Logos' description says "On a Low Roku (see Memory above)" instead of "On Rokus with 512 MB or less". A 720p UI or an unknown memory limit also makes a Roku Low.
  - After an alert: Channel Logos reads "Off: Low Memory", with "This Roku ran low on memory, so logos are off until MMTVL Live TV opens again. This switch keeps your choice for next time." Guide Window reads "12 Hours: Low Memory", with the detail "Shorter until MMTVL Live TV opens again".
  - The other texts were checked for each class and kept (tested): Low by memory, Low by its 720p UI ("Low (720p UI)"), Low with an unknown limit ("Unknown · Low"), and High.
- **Why:** The page follows the "On" / "Off: <reason>" pattern (L7), and the old description was wrong for 720p-only Low Rokus.
- **Pros:** The page says why something is off.
- **Cons:** Unreviewed wording; the lengths still need checking at 720p.
- **To reverse:** The constants in `SettingsPages.bs`.

### D53. D19: SearchView's imports slimmed; the fold tables load only for non-ASCII typing
- **Step:** 22. **Decision (Recommended):**
  - `LiveSearch.bs` is split in two. The model and texts stay in `LiveSearch.bs`, which SearchView loads. The folding, the entries, the title index and `searchProgrammes` move to `LiveSearchIndex.bs`, the same namespace, which SearchTask and TeamsTask load.
  - SearchView no longer loads `EPGMatcher.bs`.
  - ASCII text is lowercased in the view. Other text (only the Roku mobile app's keyboard sends it) goes to a `SearchFolder` node, made on first use, which loads the fold tables and folds exactly as SearchTask does.
  - QA round 1: `newFolder` and `folded` moved into their own small file, `LiveSearchFold.bs`. SearchFolder loads only that file, `EPGMatcher.bs` (the fold table) and `Unicode.bs`; the Tasks load it with the other two LiveSearch files.
  - The state's `searching` flag, set by `textChanged`, replaces the view's calls to `isSearching`.
- **Why:** Moving the narrowing into SearchTask would make it wait for the Task (busy while it builds the index, D7), so typing would no longer narrow at once. The split keeps the behaviour identical. `Search.test.bs` is unchanged and passes, and `SearchTypingTests` checks that `typedWords` equals `queryWords` and `searching` equals `isSearching` for ASCII, accented and combining-mark texts.
- **Measured** (compiled `.brs` in `out/staging`, comments included):
  - **Before:** 153,082 bytes. Theme 21,021; Unicode 10,346; EPGMatcher 35,199; TeamCatalog 8,745; TeamPicker 20,979; BannerText 4,749; MyTeams 5,416; LiveSearch 33,296; SearchView 11,915; bslib 1,416.
  - **After** (corrected in QA round 1): 105,289 bytes. LiveSearch 20,590; SearchView 12,027; no EPGMatcher. That is 77,665 bytes of code without comments.
  - **SearchFolder** (QA round 1): 124,273 bytes before (Unicode, EPGMatcher, TeamCatalog, TeamPicker, BannerText, MyTeams, LiveSearch, LiveSearchIndex). 49,396 bytes after: Unicode 10,346; EPGMatcher 35,199; LiveSearchFold 2,133; SearchFolder 302; bslib 1,416.
- **Pros:**
  - About 48 KB less on the render thread (the 35 KB fold tables included), and about 49 KB, not 124 KB, if non-ASCII is ever typed.
  - Same results and timing.
- **Cons:**
  - One more component.
  - **Unverified:** whether Roku compiles a component's scripts when the first node of it is made (so SearchFolder costs nothing until then) or when the app starts.
- **To reverse:** Merge the two files and import `EPGMatcher.bs` in SearchView again.

### D54. The DEBUG memory line: every 5 minutes, from the main thread
- **Step:** 22. **Decision (Recommended):** In DEBUG builds, `main.bs` waits at most 5 minutes on its port and then prints `[MMTVL][Memory] Using N % of the limit (GetChannelMemoryLimit M MB, available A MB); highest since launch H % (under 80 % | reached 80 %); alerts K`, plus one line at launch. The highest value counts the 5-minute samples and the alerts. All of it sits inside `#if DEBUG`, and `npm run build:release` now fails if the release staging's code (comments aside) holds it.
- **Why:** This is the step's done-when: a 2-hour stick run stays under 80 %. The main thread already has a port loop and no render work.
- **Pros:** One line answers the done-when, and the release build has none of it.
- **Cons:** A spike between samples shows only if it caused an alert.
- **To reverse:** In `main.bs` and `MemoryRelief.consoleLine`.

### D55. Left as is: Settings' animation and the one-line upcoming game
- **Step:** 22. **Decision (Recommended):** The plan's "Step 22 may revisit" items are unchanged:
  - Settings' animation (only the track slides; rows are clipped, not faded);
  - D5's one-line upcoming game cell.
- **Why:** Each needs a device to judge (fades cost render time on a stick), and neither affects memory.
- **To reverse:** Revisit after step 23's look at 1080p and 720p.

### D56. A tuner's JSON is checked for nesting before ParseJson, with the import's check shared
- **Step:** 24 (security N-3). **Decision (Recommended):**
  - The import's byte loop (`ImportBundle.depthOf`, step 14) moves to a small shared lib, `source/lib/JsonDepth.bs` (`ofBytes`, `ofText`, `fits`; about 1 KB compiled). `ImportBundle.depthOf` calls it with its limit of 3, unchanged.
  - `HDHomeRun.decodeJSON` runs `JsonDepth.fits(text, HDHomeRun.maximumJSONDepth)` before `ParseJson` for `discover.json`, `lineup.json`, `status.json` and `lineup_status.json`. The limit is **8**: these files nest 1 or 2 deep, so this leaves room for firmware differences. A deeper answer reads as no answer: `discover.json` then gives "notTuner".
  - `JsonDepth.bs` is loaded where `ImportBundle.bs` or `HDHomeRun.bs` is (MainScene, ImportConfirmView, ImportTask, AntennaTask, GuideTask). No other lib moves.
  - The function is `decodeJSON`, not `parseJSON`. BrighterScript resolves a call inside a namespace to that namespace's own function first, ignoring case, so a `parseJSON` would have turned its own `ParseJson(text)` call into a call to itself. `test:local` caught it (a stack overflow).
- **Why:** The tuner is a LAN device the app trusts only after checks. A hostile device on the LAN could answer with deep nesting to make `ParseJson` recurse. One loop for both callers means one set of tests.
- **Explained:** Before reading a tuner's answer, the app counts how deeply its brackets nest. More than 8 levels, and the answer is ignored.
- **Pros:** The same check as the import's, tested once (`JsonDepthTests`), and it stops counting as soon as the limit is passed.
- **Cons:**
  - The scan is a BrightScript loop over every byte, on AntennaTask's or GuideTask's thread. A normal `lineup.json` is tens of KB; one near the 1 MB cap would take longer (**unverified** on a stick).
  - About 1 KB more code on the render thread (MainScene and ImportConfirmView load ImportBundle).
- **To reverse:** Call `ParseJson` directly in `HDHomeRun.decodeJSON`, and put the loop back in `ImportBundle.depthOf`.

### D57. A logo needs a playlist, and a removed or changed source empties LogoTask's queue
- **Step:** 24 (security N-1). **Decision (Recommended):**
  - `URLPolicy.allowsLogo(url, playlistURL)`: with no playlist (`""`), every logo is refused (reason `noPlaylist`); otherwise it is `allows(url, playlistURL)`, as before. LogoTask's `fetch` checks it before it makes a transfer, and logs "not allowed".
  - A refusal for want of a playlist isn't remembered as failed, so the same logo loads once a playlist names it again. Other refusals and failures are still remembered for the run.
  - MainScene's `dropWaitingLogos()` sends `{ clear: true, reason: "source" }` (step 22's clear) on Remove Live TV Source, on a changed playlist (`changePlaylist`) and on an import's Replace. It is sent before the new `playlistURL`, so a logo LogoTask starts in between is judged against the playlist that named it. LogoTask logs "Live TV source changed: N waiting logos dropped" when it dropped any.
- **Why:** Logos come only from a playlist's entries. `allows(url, "")` means "typed by the user", which allows any host, LAN and loopback included.
- **Explained:** When the Live TV source is removed or changed, logos that were still waiting to download are no longer fetched.
- **Pros:** Closes the gap without changing how logos load while a playlist is set.
- **Cons:** On an import, the queue is cleared twice: once in `applyImportedSettings` and once in `changePlaylist`. The second clear finds nothing and logs nothing.
- **To reverse:** Use `URLPolicy.allows` in `LogoTask.fetch` again, and remove `dropWaitingLogos()`.

### D58. gitleaks: allowlists checked against each finding, a DeviceAuth rule, and redaction that hides the whole match
- **Step:** 24 (security N-4). **Decision (Recommended):** In `scripts/gitleaks.toml` (gitleaks 8.30.1):
  - **The `.example` allowlist** is now a finding-level `[[allowlists]]` with `regexTarget = "match"`, anchored with `^`, so a finding is allowed only when its own match starts with a `.example` URL. Until now it was a whole-line allowlist, so a real URL on the same line as a `.example` one was hidden too. RE2 has no lookahead, so "every URL on the line is `.example`" can't be written as a line regex.
  - **`credential-query`** now takes in the URL its query belongs to, when the URL is written right before it (`(?:https?://[^\s"'<>]*?)?` in front), so the anchored allowlist can judge that URL. A query with no URL before it is still found.
  - **New rule `hdhomerun-deviceauth`:** `(?i)DeviceAuth=[A-Za-z0-9+/=_%-]{8,}`. Its allowlist is also checked against the match: the whole value must be made of the tests' made-up DeviceAuths, as written or percent-decoded (gitleaks also scans percent-decoded text). The old line entries for those values are removed, so a real DeviceAuth on a fixture's line is found.
  - **Redaction:** the rules' key groups are now non-capturing. gitleaks takes a rule's first capture group as the secret, so `--redact` hid only `get.php`, `m3u8` or the query's key name and printed the rest, tokens included. Each finding's secret is now its whole match. This wasn't one of the review's findings: it came up while checking N-4, and it changes only what a scan prints.
- **Checked:**
  - With the old config's `.example` line removed, there were 22 findings on the branch's commits and 24 across the four folders, all from `iptv-playlist-url` and `credential-query` on `.example` fixtures.
  - With the new config, the branch, `roku`, `scripts`, `MMTVLTests`, `docs` and the whole history (207 commits) have none.
  - A scratch file (not committed) with a made-up provider-style URL, a credential query and DeviceAuths, each next to a `.example` URL or a made-up value on its line, gives 5 findings, each redacted in full. The old config gave 1.
- **Explained:** The leak scan no longer skips a real address just because a test address is on the same line. It now finds HDHomeRun keys, and hides everything it finds when asked to.
- **Pros:** Each finding is judged by its own text, and `--redact` output is safe to paste.
- **Cons:**
  - Fingerprints of past findings change (the secret is now the whole match). The repo has no `.gitleaksignore`.
  - A real URL inside a `.example` URL's own query (`https://a.example/r?u=https://real/...`) is still allowed, since the match starts at the `.example` URL.
- **To reverse:** Restore the file as it was before step 24.

### D59. `npm audit fix` kept: 33 high to 0, dev tools only
- **Step:** 24 (security N-6). **Decision (Recommended):** `npm audit fix` (never `--force`) in `roku/` is kept.
  - **Before:** `npm audit` said "31 high severity vulnerabilities" (its JSON metadata: high 33, total 33). **After:** "found 0 vulnerabilities" (metadata: total 0).
  - Only `package-lock.json` and `node_modules` changed, all from `registry.npmjs.org`. The direct devDependencies (`package.json` and `npm ls --depth=0`) are unchanged: bslint 0.8.47, brighterscript 0.73.8, brs-node 2.7.0, roku-deploy 3.18.4, rooibos-roku 5.17.0.
  - **Transitive changes:** `jimp` and every `@jimp/*` 1.6.1 → 1.7.0, `bmp-ts` 1.0.9 → 1.1.0, `zod` 3.25.76 → 4.6.7 (jimp 1.7.0's), `decode-uri-component` removed, `source-map-resolve` 0.5.3 → 0.5.0 (deprecated; npm's choice).
  - All four gates pass after it.
- **Why:** The plan's step 24 asked for `npm audit`, and step 2 accepted 43 high as dev-only. The fix needed no direct version change.
- **Explained:** The build tools' own dependencies were updated to versions without the known problems. None of these ships in the Roku app (the one npm package that does, bslib, isn't among them: D61).
- **Pros:** A clean audit, so a new advisory stands out.
- **Cons:**
  - `zod` is a major version newer under brs-node's jimp. Only brs-node's image handling uses jimp, and no local test exercises it.
  - `source-map-resolve` moved to an older, deprecated release.
- **To reverse:** Restore `roku/package-lock.json` from before step 24, then `npm ci` in `roku/`.

### D60. The import's confirm screen says where the bundle came from
- **Step:** 24 (security N-8). **Decision (Recommended):** `ImportBundle.summaryRows(bundle, lastChannelLabel, fromHost)` begins with a **From** row: the IPv4 address the import asked (`checkRequest`'s host, kept as `m.importHost` in the scene; "?" if empty). The script prints that address ("serving the settings from <address>"), so the user can compare the two. The frame (NgJ0S) has no such row; it uses the same row style. The panel grows by one row (57 px at 1080p; about 910 px tall in all, estimated from the Theme tokens with a two-line question and footnote).
- **Why:** Any LAN host with ECP can open the confirm screen with its own bundle (step 14's accepted L-3). With its address on screen, a bundle from another host reads as one.
- **Plan check:** the plan forbids showing a **tuner's** address (L6, D29), URLs (only hosts) and the migration secret. Nothing forbids the import's own source address, and step 14 already has the user compare IP addresses (its M-1).
- **Explained:** Before replacing settings, the Roku shows which computer on the network sent them.
- **Pros:** The user can spot an import they didn't start.
- **Cons:**
  - A LAN IPv4 address on screen (and in photos of it).
  - **Unverified:** the 8-row panel at 720p (step 23).
- **To reverse:** Drop the first row in `summaryRows` and its third argument.

### D61. bslib's MIT notice ships inside the package, and in the README
- **Step:** 25 (security N-5 of step 24). **Decision (Recommended):** `roku/licenses/bslib.txt` holds the MIT license of `@rokucommunity/bslib` 0.1.1 (© 2021 RokuCommunity), with a line saying it covers `source/bslib.brs`. `"licenses/**/*"` is in the `files` of `bsconfig.json`, `bsconfig.test.json` and `bsconfig.release.json`, so every zip carries it at `licenses/bslib.txt`. `roku/README.md` (Third-party code) and `CLAUDE.md` (Roku (M12)) name it too. The plan's L1, step 2's entry, step 24's text and D59, which said nothing from npm ships, are corrected.
- **Why:** BrighterScript's compiler adds bslib to every build as `source/bslib.brs` (1,416 bytes), so the app does ship npm code, and MIT asks for its notice "in all copies or substantial portions of the Software". A notice inside the package travels with every copy of the zip; a README alone stays in the repo.
- **Explained:** A small text file with bslib's license now rides along in the app. It is never shown on screen.
- **Checked:** `npm run build:release` went from 126 to 127 files ("Release build: 127 files, no probe code, no DEBUG memory line"), and `unzip -l` lists `licenses/bslib.txt` (1,345 bytes) in `out/mmtvl-live-tv.zip` and `out/mmtvl-live-tv-release.zip`. The other gates pass ("LOCAL TESTS: 742 passed, 0 failed").
- **Pros:** Meets the license for every copy of the app, at the cost of 1.3 KB in the package, with no code change.
- **Cons:**
  - Nothing checks that the notice matches bslib's version: a bslib update (with a BrighterScript update) needs the file changed by hand. (That the notice is there, `build:release` checks since D62.)
  - The notice isn't reachable from the app's UI (a Licenses page like MMTVL's would be new UI).
  - The test zip also holds the Rooibos framework (MIT), with no notice in it; that zip goes only to a developer's own Roku.
- **To reverse:** Delete `roku/licenses/` and the `"licenses/**/*"` lines; keep the README's notice.

### D62. The release build checks for bslib's notice; no Rooibos notice or `deploy:release`; a pointer in the root README
- **Step:** 25 (the implementer's three questions). **Decision (Recommended):** `npm run build:release` fails when `licenses/bslib.txt` is missing from the release build, like the team catalogs. The test zip gets no Rooibos notice and no `deploy:release` script is added. The root `README.md` gets one line pointing at `roku/README.md`.
- **Why:** The notice is a license duty, so a missing one should stop the build that gets installed. The test zip is never handed out (it runs on the dev Roku only), and a release build goes on through the installer page, as the README says.
- **Explained:** The check is one more entry in the list of files a release build must hold.
- **Pros:** The notice can't silently drop out; the repo's front page says the Roku app exists. **Cons:** The check proves the file is there, not that it matches bslib's version.
- **To reverse:** Remove `licenses/bslib.txt` from the list in `roku/tools/roku.mjs`; delete the README line.
