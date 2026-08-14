# 2026-08-08: Layer texture audit — 16 of 40 replaced

Tags: cake-cycle, render, config, tooling, art

## Task
"Some layer textures are completely unsuitable — many chocolate textures don't
look like chocolate at all. Screenshot every texture, review, propose
replacements, show me before replacing." User approved my pick for every flagged
category EXCEPT zone walls and sponge-red-velvet (kept as-is).

## Context
`CakeLayersConfig` (40 layers / 10 zones, split out 2026-08-07) carries
`texture`/`sideTexture` image ids gathered from the Toolbox by name. The wall
textures had already burned us once at wall size (flow
`2026-08-07_cake-zones-and-mini-bosses.md`: "a Toolbox id and its name are not
evidence") — this audit did the same at LAYER level, for all 42 unique ids.

## Plan
1. Render every unique texture id on a labeled 3D tile grid in Studio (Edit),
   over its in-game tint AND over white, `screen_capture` per page.
2. Judge each; search candidates per broken category (workflow fan-out over
   `search_asset`), resolve decal→image via `InsertService:LoadAsset`.
3. Render all candidates the same way, shortlist visually, send the user
   per-category approval sheets (current vs options), wait for picks.
4. Apply picks in config only after approval.

## Changes

**Modified:**
- `src/shared/config/CakeLayersConfig.lua` — 15 layers re-textured (16 slots:
  jelly + jelly-orange share): chocolate-white 9642508171→18903274127,
  chocolate-dubai 16395823968→18902649024 (was a cartoon pistachio CHARACTER),
  jelly/jelly-orange 128350527737770→15142269976 (was gummy-bear pile),
  jelly-lime 551772921→7185243377, jelly-berry 1024699322→71141528046438,
  butter 432595376→5386064531 (old decal was literally named "cake frosting"),
  butter-salted 432607604→5386064531 (now shares butter, tint differentiates;
  cheese-cream keeps 432607604), cheese-blue 16428265759→85021510700546,
  jam-apricot 14973309971→6302878736, jam-blueberry 1477869098→115991175913833
  (old one was a STRAWBERRY-jam label pattern with readable text),
  sponge-chocolate 115607802615807→170617913, cream-condensed
  18902685823→13304044697, toffee 11413396972→845255656 (was a wrapped
  Tootsie Roll product photo), caramel-coffee 13214376473→845275420 (was a
  recipe card with "Coffee CARAMEL" text baked in), crumb-cookie
  16023930061→109100549141423 (was Oreos-on-white, tiled as floating blobs).

**Kept (user decision):** all 10 zone wall textures, sponge-red-velvet.
**Kept (audit passed):** frosting, chocolate, nutella, butter-peanut/honey,
cheesecake, jam-strawberry, sponge/honey, filling, cotton, marshmallows,
caramel/salted, toffee→see above, crumb/biscuit/cereal.
**Borderline, untouched:** sponge-honey (washed out), WALL sponge / WALL crumb
(lavender stripe lines), WALL cheese (Swiss holes for a cheesecake zone),
cheese-cream (sprinkled frosting as "cream cheese").

## Decisions
- **Audit at render size over the in-game tint AND over white.** Tint hides
  content (sponge-chocolate read as flat brown — it is a washed-out cream crumb
  under a brown part color); white + `Lighting.ExposureCompensation = -1`
  separates "bad texture" from "pale tint + bloom".
- **All new ids are IMAGE ids** resolved from free decals via
  `InsertService:LoadAsset(decalId)` → `Decal.Texture` (the established
  pipeline; a decal id renders BLANK on a `Texture`). 111 decals resolved, 0
  failures, ~14/`execute_luau` call.
- **Resolution exposed silent duplicates**: several catalog "candidates" resolve
  to images ALREADY in the config (9642508180→9642508171 = the very cartoon
  being replaced; "TBWhippedFrostSet Vanilla"→18902662835 = current cheesecake).
  Always resolve BEFORE judging novelty.
- **Same-zone texture sharing is fine, cross-zone is not.** butter-salted now
  shares butter's image (pattern precedent: jelly-orange, caramel-salted,
  cotton-blue, jam-cherry). Candidates that would have duplicated one image
  across two ZONES (purple slime for both jelly-berry and jam-blueberry) were
  split so each zone keeps a distinct image.
- **Capture tooling (the reusable part):** `screen_capture` in Edit mode does
  NOT show CoreGui ScreenGuis (contradicts a 2026-07-31 note — Studio changed),
  and SurfaceGui text renders as unreadable mush at tile-label size. What works:
  textures on part TOP faces shot top-down, then crop tiles OUT of the capture
  files (`%LOCALAPPDATA%\Roblox\tmp-capture-storage\wob-*`, map to captures by
  mtime) with a pinhole projection from the known camera pos/look-at/FOV-70 —
  zero detection, pixel-exact — and compose labeled sheets in PIL
  (scratchpad `compose_sheets.py`, this session).
- Verification for a texture-id data swap = the tile renders themselves (every
  new id was live-rendered in Studio before being proposed) + `luau-compile`
  gate + Studio `.Source` sync check. No playtest: no behavior changed.

## Open Questions / Followups
- Borderline set above if the user ever wants a second pass.
- Adversarial review WARN (pre-existing): `18902662835` is the one CROSS-zone
  cap share left — cheesecake/cheese-mascarpone (cheese zone) and
  cream-whipped/cream-vanilla (cream zone). Tint-differentiated, walls differ,
  so only crater cross-sections blur; queue a distinct cream texture if it ever
  reads wrong in play.
- `push`-era note: nothing here touches localization or the cloud table.

## Related
- Feature: `docs/features/cake-cycle.md` (zones table + texture gotcha)
- Prior flow: `docs/flow/2026-08-07_cake-zones-and-mini-bosses.md`
