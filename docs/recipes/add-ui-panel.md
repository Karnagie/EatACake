# Add a UI panel / any player-facing UI

Do NOT design UI ad-hoc. The entire procedure (composition catalog, generative
style rules, grid/scroll math, verification checklist) is the skill:

1. Read `.claude/skills/roblox-ui-kit/SKILL.md` and follow its workflow.
2. References inside it: `references/components.md` (what exists),
   `references/style-rules.md` (how to make new elements),
   `references/patterns.md` (panel walkthrough + pitfalls).
3. Integration contract (mounting, setup, R-rules interplay):
   `docs/features/ui-kit.md`.

Definition of done: skill's Studio verification checklist passed, no console
errors, docs updated per D2.
