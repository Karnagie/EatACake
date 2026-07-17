# 2026-07-15: UI Kit port + roblox-ui-kit skill

Tags: ui-kit, ui, skill, packages, bootstrap

## Task
Port the candy-style ReactRoblox UI kit (built and verified live in the
`uitest` Studio place) into the template, and codify the style knowledge as an
agent skill so any model can produce the same UI quality when building
features ("make a shop" → correct UI comes with it).

## Context
Template had no UI layer beyond the `UiData` ScreenGui resolver; the old UI
workflow assumed Studio-authored GUIs. The kit was developed and visually
verified in a separate Studio place: Settings panel (original style source),
Pets grid panel, PetsInspect panel (inspector sidebar), HUD with panel
toggling — all interactions click-tested in play mode.

## Plan
Copy sources verbatim from the verified place; adapt only require paths
(`UI.Settings` → `Shared.UIKit`, demos in `Demos/` subfolder). Add npm-based
React deps (jsdotlua) with rojo mapping. Write the skill as the single source
of style knowledge; feature doc carries only the integration contract.

## Changes

**Created:**
- `src/shared/UIKit/` — `init.lua` (facade), `Theme.lua` (single style
  source), `Components/` (16: OutlinedText, Button, Toggle, CloseButton,
  Header, PanelShell, PanelWithHeader, SettingRow, SettingsPanel, IconButton,
  ScrollPane, PetCard, PetsPanel, PetsInspectPanel, StatPill, Hud),
  `Demos/` (Selector + Settings/Pets/PetsInspect/Hud reference apps)
- `src/client/modules/UiRoot.lua` — React root owner (Init/Render/Unmount)
- `Packages/React.lua`, `Packages/ReactRoblox.lua` — jsdotlua npm loaders
- `package.json` — @jsdotlua/react + react-roblox + npmluau (prepare)
- `.claude/skills/roblox-ui-kit/` — SKILL.md + references (style-rules,
  components, patterns)
- `docs/features/ui-kit.md`, `docs/recipes/add-ui-panel.md`

**Modified:**
- `default.project.json` — ReplicatedStorage.Packages mapping (node_modules
  as optional path so rojo works pre-`npm install`)
- `.gitignore` — node_modules, package-lock
- `CLAUDE.md` — UI Workflow section rewritten kit-first (Studio-authored path
  kept for bespoke non-kit visuals)
- `docs/MAP.md` — ui-kit feature row + infra rows (UiRoot, npm loaders)

## Decisions
- **Kit as `Shared.UIKit` folder-with-init** — one require returns Theme +
  Components; demos lazy via folder ref.
- **Sources copied verbatim from the verified place** (not rewritten) — the
  visual math was screenshot-verified there; only require paths differ.
- **Skill = single source of style knowledge** (D3): feature doc deliberately
  thin, points to the skill. Skill is written for weaker models: iron rules,
  mechanical generative recipes with exact numbers, copy-this-component
  guidance, mandatory Studio verification checklist, pitfall list.
- **node_modules as optional rojo path** — builds don't break before
  npm install; UiRoot degrades with a Log.Warn (R8) instead of erroring.
- **R4/R5 interplay recorded in feature doc**: React-internal events =
  library-internal exemption; React tree = declarative template (no
  Instance.new hand-building for kit UI).

## Open Questions / Followups
- `npm install` not run here (no Node in this session) — first run pending;
  loaders/versions may need a pin if jsdotlua publishes a breaking 17.x.
- Live re-verification of the kit inside the template place (studio-verifier)
  pending — the code is verbatim from a verified place, но the rojo/npm
  plumbing is new.
- Window manager / notification badges (planned "glue") should build on
  `UiRoot` + the `openPanel` pattern from `HudDemo`.
- `Theme.Hud.Icons` are placeholder assets; replace per game.

## Related
- Feature: `docs/features/ui-kit.md`
- Skill: `.claude/skills/roblox-ui-kit/SKILL.md`
- Recipe: `docs/recipes/add-ui-panel.md`
