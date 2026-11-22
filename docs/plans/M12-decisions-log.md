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
