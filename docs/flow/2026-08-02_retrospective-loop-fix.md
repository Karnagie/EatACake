# 2026-08-02: Retrospective — why the template stopped improving, and the fix

Tags: self-improvement, upstream, harvest, process, docs

## Task
User asked for a retrospective over the project (improvements, skills,
knowledge, mistakes) and an update to `D:\Projects\Roblox\RobloxTemplate`,
with the observation that the promised per-task template improvement either
was not happening or was broken. Business logic must not reach the template —
only what any project can reuse (UI styles, tooling, skills, fixes).

## Context
Audit of both repos (13 parallel readers over the 200-row queue plus
structural diffs of infra, tools, skills, UI kit and docs):

| | |
|---|---|
| Rows captured, 2026-07-12 → 2026-08-02 | **200** |
| Rows ever `harvested` | **0** |
| Rows ever `rejected` | **0** |
| Template's newest changelog entry | 2026-07-23, from template-side work |
| Template git history | 1 commit |

**U1 (capture) was working perfectly. U3 (harvest) had never fired once.**
So the instructions were not being ignored — the loop was missing its second
half.

## Diagnosis
1. **No trigger** — harvest ran "on the user's request"; nothing measured
   depth, age or severity, so the only closing move depended on a human
   remembering an invisible file.
2. **Entry cost was the whole queue** — the recipe demanded a viability
   verdict on every pending row before any porting (~44k tokens at 200 rows),
   so deferring was always the cheapest action.
3. **No unit smaller than "all 200"** — no ids (nothing could reference a row
   from the other repo), no priority (a money bug sorted equal with a
   nice-to-have), no length cap (rows averaged ~890 chars).
4. **Monotonic by design** — settled rows were specified to stay, so depth
   could never fall.

## Changes (this repo)
- `CLAUDE.md` — NEW **U1b** depth trigger; U3 gains the ≤10 batch bound,
  grep-triage, P1-first, and "a settled row LEAVES the queue"; Post-Task
  checklist split into Upstream capture (U1) / Upstream depth (U1b).
- `docs/upstream/QUEUE.md` — row contract documented; all 200 rows backfilled
  with `EAC-0001..0200` ids + priorities **by script** (5 × P1, 191 × P2,
  4 × P3). No row text rewritten — ids and the `P` column only.
- NEW `docs/upstream/ARCHIVE.md` — settled rows leave the queue and land here
  by ID.
- `git remote add template` for pull-down.
- 3 new rows captured from this task itself (`EAC-0201..0203`).

Template side (commits `651b085`, and the `.gitattributes` capture): the
`harvest` skill, ARCHIVE.md, the rewritten contract, the copy recipe, the
ProfileStore ~30s→~300s fact fix, and the 13 remaining audited packages
recorded as `TPL-0005..0018`.

## The 5 P1 rows — defects the template still ships
`EAC-0053` unbounded `WaitForChild` in `Net` (hangs the whole bootstrap;
pcall does not save you, it catches errors not yields) · `EAC-0026`
`AppRoot.Set` cannot clear a field, so no template panel closes by its X ·
`EAC-0052` `ProcessReceipt` not idempotent for consumable dev products ·
`EAC-0024` no rate limit on resync-answering remotes · `EAC-0025` jsdotlua
nil-in-deps. Plus `EAC-0201` (missing `.gitattributes`).

## Mistake made during this task, and its lesson
The backfill script picked its line separator with `if b"\r\n" in raw`. The
queue file has **mixed endings** (5 CRLF among 210 LF), so it split 216 lines
into 6 chunks, processed 5 rows instead of 200 — and printed a clean success
summary. Caught only by verifying the row count afterwards. Captured as
`EAC-0201`; the general rule is in the same row: a script's self-report is not
evidence, the count is.

## Deliberately NOT done
- Stop/SessionEnd hooks (fragile on Windows; they would automate capture, the
  half that already works).
- A scheduled "harvest day" (violates U2's "user is aware"; growth is bursty).
- Splitting QUEUE.md into several live files (breaks the single grep the
  trigger depends on).
- The 13 remaining harvest packages — they are captured as `TPL-0005..0018`
  and are what the next `/harvest` run consumes.
