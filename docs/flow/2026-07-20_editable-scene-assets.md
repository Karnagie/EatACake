# 2026-07-20: Static scene → editable ReplicatedStorage.Assets (clone, not build)

Tags: map, checkpoint, assets, mapservice

## Task
User: "Remove the code-based spawning of all static assets, including the
background and environment. Every static asset should be stored in
ReplicatedStorage… checkpoint, fat-burning machine, upgrade computer, and so on.
I need to be able to manually edit or replace these assets, because the models
generated through code are very poor." (Task 1 of a 4-part overhaul.)

## Context
`MapService.Build` procedurally `Instance.new()`-built the entire static scene
(candy room + checkpoint platform, ~500 lines). The cake heightfield + its
collision columns are live sim (not art) → stay procedural.

## Decisions (confirmed with the user + ADR-0007)
- Assets **place-authored** under `ReplicatedStorage.Assets` (NOT Rojo/git); code
  resolves them by name. User edits in Studio + SAVES the place.
- Initial models **migrate the current look** (so nothing regresses); the user
  replaces them at their own pace.

## Changes
**Modified — `src/server/services/MapService.lua` (rewritten):**
- Geometry moved into private generators `buildEnvironment(parent)` /
  `buildCheckpoint(parent)` — the OLD look, kept ONLY to seed the templates.
- `MapService.GenerateAssets()` — ensures `ReplicatedStorage.Assets` holds
  `Environment` + `Checkpoint` Folders, GENERATING any missing one (self-heal),
  idempotent. Run once in Studio (Edit) to author + save; also called by Build.
- `MapService.Build()` — removes strays, `GenerateAssets()` (self-heal), CLONES
  `Assets.Environment` → `workspace.Map`, CLONES `Assets.Checkpoint` →
  `Map.Checkpoint`, resolves named parts, creates the (functional) CakeSpawn, sets
  Lighting, `SetCheckpointHeight`.
- `resolveEnvironment`/`resolveCheckpoint` — cache refs from the clones.
  Environment biome parts resolve by a `BiomeRole` attribute (opt-in recolor);
  checkpoint parts by NAME (single BaseParts).
- `SetCheckpointHeight`/`GetCheckpointCFrame`/`NearGym`/`IsOverCheckpoint`/
  `ApplyBiome` — unchanged logic on the resolved parts; `checkpointCenter` from
  config.
- `src/server/data/MapConfigData.lua` — header note (numbers now seed the default
  generator + drive checkpoint/biome runtime logic).
- Docs: ADR-0007, `features/checkpoint.md` (named-asset contract), MAP, MapService
  header.

**Authoring (one-time, Studio Edit via MCP):** generated `ReplicatedStorage.Assets`
(Environment 273 parts + Checkpoint 11 parts) — the user SAVES the place to keep
them (and then edits/replaces the models).

## Decisions (design)
- **Self-heal generator, not hard-fail.** A fresh repo clone with no authored
  assets still boots (GenerateAssets makes the default look); runtime-generated
  models don't persist, so the console/doc tells the user to author + save.
- **Biome recolor opt-in via `BiomeRole` attribute.** The per-biome room skin
  (gameplay) survives on role-tagged parts; a re-authored part without the
  attribute keeps its own colour — the user has full colour control.
- **Checkpoint is dynamic** → resolve + position NAMED single BaseParts (edit the
  look, keep the names). The environment is static → fully user-authorable.

## Verification (Studio, live)
- Boots clean; scene clones identically (walls, props, candles, checkpoint, cake).
- `ReplicatedStorage.Assets` = Environment(273) + Checkpoint(11 w/ prompts).
- Checkpoint clones + positions: plate top Y=60, 4 legs telescope, machine at the
  outer edge, `GymPrompt` + `UpgradeStation` prompts + screen intact; gym drain +
  teleport still work.
- **Edit flows to the clone**: a marker attribute + geometry set in
  `Assets.Environment` appears on `workspace.Map` at boot.
- **Opt-in recolor**: floor with `BiomeRole="floor"` → recoloured to the biome;
  ceiling with the role removed → kept the user's colour.

## Adversarial-review fixes (all applied)
- **CRITICAL #1**: re-authoring a checkpoint part as a MODEL (the primary intended
  edit) crashed `SetCheckpointHeight` (`.CFrame`/`.Position` throw on a Model),
  aborting `CakeSubs.Start` → dead game. Fix: checkpoint refs are `PVInstance`
  (BasePart OR Model), positioned via `PivotTo`, sized via `GetExtentsSize`;
  `NearGym` uses `GetPivot().Position`.
- **#3**: positioning now uses each part's AUTHORED size (plate/machine/computer/
  screen) + `IsOverCheckpoint` uses the plate's real size (matches the client
  proximity check); legs keep their X/Z cross-section (only Y telescopes). Header
  + checkpoint doc corrected (parts are Models/resizable; POSITION is code-driven).
- **#4/#5**: `resolveEnvironment` warns on a fully-unresolved (floorless) scene;
  `GenerateAssets` treats an empty/non-container template as absent and rebuilds.
- **#6**: `mapFolder` (build guard) is set only AFTER parenting, so a mid-build
  throw can't orphan + block a retry.

## Open Questions / Followups
- **User must SAVE the place** to persist the authored `ReplicatedStorage.Assets`
  (place-authored, not in git). Until then the self-heal regenerates the default
  each boot.
- **#2 (double replication)**: the templates live in ReplicatedStorage.Assets AND
  clone into workspace.Map, so the scene replicates ~twice (negligible for the
  simple-part default; strip post-clone or use ServerStorage if authored assets
  get heavy). Kept in ReplicatedStorage per the user's explicit request.

## Related
- ADR-0007 (place-authored scene assets), `features/checkpoint.md`
- Prior: `2026-07-19_checkpoint-platform.md`, `2026-07-19_easy-mode-balance.md`
- Upstream: `docs/upstream/QUEUE.md` (code-built scene → editable assets;
  execute_luau clone-require gotcha)
