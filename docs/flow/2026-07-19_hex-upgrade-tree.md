# 2026-07-19: Hexagon upgrade tree + checkpoint computer

Tags: upgrades, ui-kit, checkpoint, map, persistence, stats, hexutil

## Task
Redo the upgrades visual: (1) open them from a "computer" standing on the
checkpoint via a prompt, not a HUD button; (2) a hexagon skill-tree (honeycomb)
that gradually unlocks, where some hexes open a nested local sub-tree with a
centre "back" hex. Rework the progression to suit (40 hexes for one stat = too
much). Reference screenshot: a compact honeycomb, states gray/gold/blue, hover
tooltip, currency top-left, "Close [E]".

## Context
Upgrades were a flat portrait panel (`UpgradesPanel` + `UpgradeRow`) opened from
a HUD menu button; six stats each bought as 15–40 LINEAR levels (`cost =
base·growth^level`). The checkpoint platform (`features/checkpoint.md`) already
carried the gym machine + a ProximityPrompt. Kit is scale-first ReactRoblox
(`.claude/skills/roblox-ui-kit`).

## Plan
Full-screen candy OVERLAY (not a window). 3 themed categories (eating/body/gym)
→ nested sub-trees of tier-chains. Repackage-keep-power rebalance: fold each
stat's many levels into ~5 TIERS whose value = old formula at the boundary and
cost = sum of the old levels replaced. Hex = a white flat-top hex sprite stacked
Outer/Rim/Face, tinted per state by UIGradient (a shape UICorner can't make).
Auto-fit each tree's bounding box into a square canvas so root + sub-trees fill
the view. Open via the station prompt (client-local); E / Close button close.

## Changes

**Created:**
- `src/shared/HexUtil.lua` — redblobgames axial hex math (flat-top ToPixel/
  FromPixel/Round/Dimensions/neighbours).
- `src/shared/config/UpgradeTreeConfig.lua` — honeycomb graph (root categories +
  per-category stat arms) + hex ratios (nodeFill/connectorThickness/pad).
- `src/client/modules/LocalUpgradeTree.lua` — view-model: axial nodes/edges →
  auto-fit Scale positions + states (locked/available/owned/category/back/logo).
- `src/shared/UIKit/Components/HexNode.lua`, `HexTreeOverlay.lua` — the hex node
  + the full-screen overlay (scrim, canvas, connectors, currency, close, tooltip).

**Modified:**
- `config/UpgradeConfig.lua` — per-tier `{value,cost}` arrays + categories
  (rebirth block unchanged).
- `ProfileSchema/UpgradesSection.lua` — v1→v2 migration (linear level → tier
  rescale, `round(lvl/oldCap*5)`).
- `StatsService`/`LocalStatsService` — `upgradeValue` reads `def.tiers[tier].value`;
  NextCost from `def.tiers`.
- `UpgradeService` — NextCost/ApplyLevel use `def.tiers` (nil past last = maxed).
- `MapConfigData`/`MapService` — build the `UpgradeStation` computer (body +
  neon screen + prompt) on the plate; ride it in `SetCheckpointHeight`.
- `AppRoot` — swapped `UpgradesPanel` → `HexTreeOverlay`; removed the Upgrades
  HUD button; added `treeStack` nav state + reset-on-open effect.
- `UpgradesSubsClient` — prompt→open, E/blur/prompt-disable while open.
- `UIKit/Theme.lua` — `Theme.HexTree` (hex sprite id, per-state gradients,
  tooltip, scrim, canvas). `UIKit/init.lua` — register HexNode/HexTreeOverlay.
- `LocaleData.lua` — `cat-*`, `hex-*`, `hex-name-*`, `upgrade-*-desc` keys.

## Decisions
- **Overlay, not a window** (user choice): the honeycomb needs space; the
  reference is a blurred full-screen layer. → ADR-0005.
- **Hex sprite is the one chrome image.** UICorner only makes rounded rects; a
  hexagon needs a sprite. Generated a white flat-top hex PNG (System.Drawing),
  uploaded via Studio MCP → `rbxassetid://125037319877300`, stored in Theme like
  `Hud.Icons`. Chose an uploaded texture over runtime EditableImage because this
  machine's Editable* budget is tight (memory note) and a normal texture avoids
  it entirely.
- **Auto-fit layout** (bounding-box normalize into a SQUARE canvas) so the
  compact root and spread sub-trees both fill the view; square canvas keeps Scale
  positions/rotations undistorted (connector-bar rotation trap).
- **Tier rework preserves power + grind**: tier value = old formula at boundary,
  tier cost = Σ of replaced levels. Remote contract unchanged (`BuyUpgrade(statId)`
  advances one tier) — server flow untouched, still exploit-safe.
- **Prompt disabled while open**: it uses E, so E-to-close would re-open it; also
  hides the overlapping prompt UI.

## UX pass (v2, same day — user feedback)
Reworked for "plays great on PC + phone, a child gets it":
- **Dense touching honeycomb** (was straight arms + connector bridges): sub-tree
  tiers PACKED into a blob, each stat an angular-sector wedge-clump
  (`packSectors`), hexes edge-to-edge (`nodeFill = 1`), connectors removed.
- **Modal**: camera frozen (`Scriptable`) + movement disabled + all checkpoint
  prompts off while open; red X close top-right.
- **Tap-to-detail**: hover tooltip → a bottom Detail card (name/desc/status +
  green Buy button) opened by tapping a tier — the primary buy path on PC AND
  touch (tap = click). `calories` re-enters `BuildTree` (badges + affordability).
- **Category notifier BADGE** when an affordable next-tier sits inside.

## UX pass (v3, same day — user feedback #2)
- **Zoom + pan the tree** (the earlier "camera lock" misread the ask): the hexes
  live in a `World` frame with ZOOM/PAN bindings inside a clipped `Viewport`;
  drag pans, +/-/1x buttons + scroll + pinch zoom (zoom keeps the cursor point
  fixed, pan clamped, reset on tree change). Hexes became NON-interactive; a
  single transparent full-screen Active `InputSurface` (above hexes, below
  controls) catches ALL input and HIT-TESTS taps to the nearest hex — the robust
  way to pan under clickable nodes (input over a non-active child doesn't fall
  through reliably). The modal camera/movement freeze stays (prevents the game
  camera zooming on scroll; scroll is gameProcessed on the surface anyway).
- **Notifier is a red "!"** circle (was a green dot), dynamic with calories.
- **Detail card appears NEXT TO the tapped hex** (was bottom-centre), flips
  left near the right edge, clamped on-screen.
- Verified live: drag-pan, +/- zoom, near-hex card, and the AFFORDABLE buy
  through the card (calories −390, next tier unlocked, badge updated). Scroll +
  pinch use the same surface but couldn't be emulated via the Studio MCP.
- Review fix (CRITICAL): `GuiObject.InputEnded` isn't delivered when a release
  lands on a higher-Z control → a drag ending on a button leaked the input-ref
  map and soft-locked pan/zoom. Fixed by running drag/pinch/END on
  `UserInputService` (global, via refs in a `useEffect`) — only press-START stays
  on the surface (so a pan must begin on the tree); onEnded only reconciles
  tracked inputs; reset effect clears the input refs. Verified: a drag ending on
  a control no longer breaks the next drag. Also: pinch-end no longer fires a
  phantom tap (moved=true on 2→1), and the Detail card is Active so taps on it
  don't hit a hex behind it.

## UX pass (v4, same day — user feedback #3)
- **Pan clips only at SCREEN edges** (was a small square window): full-screen
  `Clip` wraps the square `Viewport` (now non-clipping); the World overflows it.
- **Card dismisses** on drag, empty-space tap, or re-tapping the open tier.
- **"!" notifier in a TOP layer** (World child, z+6) so packed neighbours can't
  cover it; z-bands reshuffled (hexes z+2..5, badge z+6, InputSurface z+7,
  controls z+8, card z+10); the card is an Active button (inert to the pan
  surface).
- **Show only owned + available + next tier** per stat
  (`min(owned+2, #tiers)`, `packSectors(counts)`); deeper tiers appear as you buy.
- Debugging note: taps appeared to "miss" under the Studio MCP — the harness
  clicks in Studio-window space (a fixed +X offset from the play-area GUI space),
  while `input.Position` and `AbsolutePosition` share GUI space (verified: Y
  matched exactly). So NO GUI-inset conversion is needed in the hit-test; a
  toLocal(inset) attempt was reverted. Verified with harness-corrected clicks:
  tap→drill, tap→card→buy, re-tap/drag dismiss, per-stat visible tiers all work.
- Review fix (WARN): the Detail card is pinned to a screen point, so ZOOM and
  BUY (which now reflows the tree — `counts` grew) detached it from its hex.
  Fixed by dismissing the card in `zoomAround` and after a buy (it's a transient
  popup; tap the next tier to keep buying). Verified: zoom → card gone; buy →
  card gone + reflow ([1,2] → [1,2,3]) + calories −450. Also: reset clears
  `focus`, and the currency chip is Active (a drag from it no longer pans).

## Open Questions / Followups
- Per-stat/category ICONS were skipped (text-forward nodes); reuse/upload icons
  later if wanted.
- HexNode's inline notifier is now dead (badges render in the overlay) — prune.
- Old `UpgradesPanel`/`UpgradeRow` + `Theme.UpgradeRow`/`UpgradesLayout` +
  `Theme.HexTree.Tooltip` are now unused (kept to avoid touching demos); prune
  in a cleanup pass.
- Rojo new-file double-sync bit again (all 5 new files duplicated) — deduped in
  Edit; see the memory note.

## Related
- Feature: `docs/features/upgrades.md`, `docs/features/checkpoint.md`
- ADR: `docs/decisions/0005-hex-tree-overlay.md`
- Skill: `.claude/skills/roblox-ui-kit`
- Prior flow: `docs/flow/2026-07-19_checkpoint-platform.md`
