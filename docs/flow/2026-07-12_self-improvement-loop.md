# 2026-07-12: Self-improvement loop (U1-U4)

Tags: self-improvement, upstream, agents, template

## Task
Make the template improve itself from game work: agents notice repeated /
generalizable things during tasks and flow them back to RobloxTemplate, plus
web research for new practices. Hard requirement: NO degradation; no manual
retrospectives needed.

## Plan
Capture cheap and mandatory, apply expensive and gated. Game sessions only
append candidates to a queue (one row, in the Post-Task Checklist); template
changes happen exclusively via a harvest protocol with five anti-degradation
gates. Research enters through the same queue, never directly into code.

## Changes

**Created:**
- `docs/upstream/QUEUE.md` — append-only candidate queue (types: fix /
  feature / contract / recipe / research / docs; statuses pending /
  harvested / rejected-with-reason)
- `TEMPLATE_CHANGELOG.md` — one line per harvested change; lets existing
  games pull improvements down by diffing against entries newer than their
  copy date
- `docs/recipes/harvest-to-template.md` — the only path for game→template
  code changes; per-candidate atomic git commits; rejection discipline
- `docs/recipes/new-project-from-template.md` — copy checklist (what to
  rename, what to keep, why CLAUDE.md is not edited)
- `.claude/agents/research-scout.md` — sourced evidence reports with
  adopt/watch/reject verdicts; U4 bias codified ("newer is not better")

**Modified:**
- `CLAUDE.md` — new section "Self-Improvement Loop — PERMANENT RULES"
  (U1 capture, U2 no silent template edits, U3 harvest gates, U4 research);
  intro explains copy model; Post-Task Checklist gets the U1 item; agents
  table gets research-scout
- `docs/MAP.md` — Lookup rows for queue/changelog/new recipes

## Decisions
- **Asymmetry is the safety mechanism**: capture costs one queue row and is
  never judged in-session (so nothing is lost); harvest judges with full
  template context + adversarial review + live verification (so nothing bad
  gets in). The queue is the ONLY interface between games and template (U2).
- Rejected rows stay in the queue with reasons — institutional memory against
  re-proposing the same idea.
- Research findings are evidence-gated (primary sources, dates) and enter as
  queue candidates; "cleaner/more modern/more popular" explicitly do not
  qualify as wins (U4).
- Since games are copies, the U-rules ship inside CLAUDE.md and propagate to
  every new project automatically — the loop needs zero per-project setup.
- Git is the rollback net: harvest requires a clean tree and commits per
  candidate. (Template repo should be `git init`-ed — user action.)

## Post-research validation (same day)
Checked the design against published practice ("compounding engineering" —
Every/community; template-propagation tooling — cruft/copier):
- Confirmed: capture→codify→reuse loop, review-gated application (industry
  does PR-based template updates — harvest is the same minus hosting).
- Adopted fix #1: **codify locally first, queue second** (U1 addendum) —
  community pattern "user correction becomes a rule immediately"; a lesson
  living only in the queue doesn't help tomorrow's session.
- Adopted fix #2: **games are git clones with a `template` remote**, not
  folder copies — pull-down becomes `git fetch template` + reviewed
  cherry-picks (industry: copier/cruft update PRs); changelog stays as the
  human-readable index.
- Deliberately NOT adopted (queued as watch, per U4): Stop-hook capture
  automation (fragile on Windows, unproven win), copier/cruft tooling
  (Python-ecosystem dependency; git approach suffices at current scale).

## Open Questions / Followups
- After 2-3 real games: revisit gate strictness (too strict → queue rots;
  measure harvested/rejected ratio).
- Optional: scheduled monthly research-scout run over core topics
  (persistence, networking, Luau features).
- U1 capture quality depends on session discipline — adversarial-reviewer
  could flag "this looks queue-worthy" as a nudge (watch how it goes first).

## Related
- Rules: CLAUDE.md U1-U4, D2, R8
- Prior flow: `2026-07-12_task-shaped-agents.md`
