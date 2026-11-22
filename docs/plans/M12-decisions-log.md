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

