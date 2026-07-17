# 2026-07-15: UI skill — method.md (the working process itself)

Tags: ui-kit, skill, design, method

## Task
Even with archetypes, an agent-built Shop disappointed. User directive:
capture HOW the original kit author actually worked — the process that made
Pets the best window (style preserved + new elements invented + genre-correct
structure) — so the same model reproduces it and the session's knowledge
doesn't evaporate. (Re-created after a repo rollback deleted the first
version of these files; SKILL.md also carried trailing NUL bytes from the
rollback — cleaned by full rewrite.)

## Context
Skill v2 had rules + catalog + archetypes, but no PROCESS: nothing forced a
written design brief, closing arithmetic, ratio-derived new elements, or the
verify-fix loop. Retrospective of the original sessions showed those four
practices were exactly what distinguished the good windows.

## Changes

**Created:**
- `.claude/skills/roblox-ui-kit/references/method.md` — the process as
  mandatory phases: A study; B written design brief (archetype, orientation,
  zones, FULL state list, props shape); C zone arithmetic with check-sums
  that must close exactly (Pets sums as example: 6*135+5*12=870,
  870+12+22=904); D new-element derivation by ratio transfer with real
  derivations (Chip = Toggle outer + navy face; scrollbar thumb = mini
  Button; PetCard = Button recipe turned portrait; bolt glyph = 3 iterations);
  E build order (render the skeleton BEFORE filling elements); F visual
  iteration loop (zoom every new element, live scale-up inspection, numeric
  drag verification, 2-4 loops is normal); G ship gate (report archetype /
  new components / iteration count).

**Modified:**
- `SKILL.md` — full rewrite: workflow section routes through method.md
  phases; references list leads with it; mounting note matches the current
  vendored-React / UiRoot contract; trailing NUL bytes removed (file was
  detected as binary by grep, breaking grep-based agents).

## Decisions
- Process encoded as PHASES WITH DELIVERABLES (brief text, sums-in-comments,
  discrepancy lists, iteration report) — weak models comply with artifacts
  better than with vibes.
- One-shot completion explicitly labeled a red flag; iteration counts belong
  in the final report so skipping Phase F is visible.

## Open Questions / Followups
- Consider a `ui-designer` subagent wrapping this method for context
  isolation on big windows.
- Redo the Shop per method.md + archetypes as the acceptance test of the
  skill fix.

## Related
- Feature: `docs/features/ui-kit.md`
- Prior flow: `2026-07-15_ui-skill-design-step.md`, `2026-07-15_ui-kit-port.md`
