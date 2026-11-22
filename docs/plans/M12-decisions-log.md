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
