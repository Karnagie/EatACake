# 2026-07-15: UI skill — mandatory design step + window archetypes

Tags: ui-kit, skill, design

## Task
First real use of the `roblox-ui-kit` skill ("make a shop with dev products
and passes") produced a Pets clone: landscape panel, card grid, BUY instead of
labels. User verdict: the skill over-weighted "reuse existing components" and
agents stopped designing window structure and inventing elements. Expected: a
genre-typical Robux shop — vertical sectioned list (passes / products), rows
with icon, name, description, price button. Window structures must match what
the Roblox audience knows.

## Context
`.claude/skills/roblox-ui-kit/` v1: iron rule #1 said "compose existing
components first; only write a new component when no composition works", and
patterns.md's walkthrough literally used a Shop as the GRID example telling
agents to copy PetCard. Both actively caused the failure.

## Plan
Rebalance: style stays locked, structure becomes a mandatory design decision
sourced from genre conventions; inventing new components declared the normal
path (with the kit's own history as precedent).

## Changes

**Created:**
- `.claude/skills/roblox-ui-kit/references/window-archetypes.md` — canonical
  Roblox window structures per feature type (shop, currency tab, inventory,
  settings, quests, daily rewards, codes, eggs, upgrades, teleports, confirm
  dialog, HUD) + fully worked Shop design (zones in nominal px, 4 new elements
  with geometry: SectionHeader, ShopItemRow, PriceButton, FeaturedBanner, data
  shape, why-not-a-grid rationale).

**Modified:**
- `SKILL.md` — "you are a UI designer, not an assembler" framing; iron rule #1
  is now "design structure from genre conventions first"; workflow starts with
  a written design step + element inventory ("zero new components for a novel
  window type is suspicious"); references list updated.
- `references/patterns.md` — walkthrough retitled to collection-window (grid
  is for collections), routes archetype choice to window-archetypes.md; added
  "vertical list in ScrollPane" pattern (UIListLayout + AutomaticCanvasSize.Y,
  rows sized by aspect constraint — stable, unlike scale heights vs growing
  canvas).

## Decisions
- Fixed vs free split codified: **fixed** = palette, layer recipe, text
  system, Theme discipline, component APIs; **free (mandatory to design)** =
  window structure, orientation, new elements.
- Archetype knowledge embedded in the skill rather than left to per-task
  research — weaker models get the genre answers directly.
- Failure mode named in SKILL.md: "new window that looks like an existing kit
  panel with relabeled cards = skipped design step".

## Open Questions / Followups
- Shop implementation itself is still to be built (now per the worked
  example); consider harvesting the resulting SectionHeader / ShopItemRow /
  PriceButton back into the kit as shipped components.
- Archetype list will grow (trade, leaderboard, battlepass) — add rows as
  features appear.

## Related
- Feature: `docs/features/ui-kit.md`
- Prior flow: `docs/flow/2026-07-15_ui-kit-port.md`
