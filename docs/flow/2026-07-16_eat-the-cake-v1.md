# 2026-07-16: Eat the Cake v1 — the whole game from the GDD

Tags: cake-sim, cake-cycle, treasures, body-gym, upgrades, pets, rebirth,
quests, juice, economy, app-root, ui-kit, map, leaderstats

## Task
Implement the "Eat the Cake" GDD v1 on the template: granular-heightfield
cake (bite + angle-of-repose slumping), full loop (eat → belly → gym →
upgrades → boss → pet → new cake), pets/rebirth/quests/monetization,
ASMR juice layer, kit UI. GDD: `Eat-the-Cake-GDD-EN.md` (user-provided).

## What landed (headline)
**Shared:** `GridUtil` (u16 heightfield math), `CakeOps` (bite math shared
for client prediction), `config/` — Cake/Upgrade/Body/Pet/Treasure/Juice
configs (ADR-0004). **Server:** cake triad (CakeFieldService settle
automaton + delta/snapshot sync, CakeCycleService phases + rare cakes +
biomes, CakeCollisionService 8×8, TreasureService, CakeSubs tick fabric +
EatAt anti-cheat), body triad (Stomach/Gym + BodySubs prompt sessions +
payouts), StatsService (derived stats, R3-legal), Upgrade/Pet/Progress/
Quest services + subs, EconomyService v2 (calories+gems, gold→gems
migration), MapService (code-built factory), LeaderboardSubs; reward kinds
calories/gems/boost/burn/egg; hourly rare-cake event. **Client:**
LocalCakeField (mirror + prediction), CakeRenderer (EditableMesh w/
part-grid fallback), juice pools (Sound/Particle/Numbers, CameraShake,
Combo, BodyMorph via attributes, PetFollowers, BossView), CakeSubsClient
(input/FX/sync), feature subs; AppRoot rework (HUD chips + 9 panels + 2
overlays), 12 new kit components (built by a 7-agent workflow), Theme
sections with zone arithmetic. 20 remotes/updates total (see registries).

## Decisions
- Heightfield over voxels/Terrain/parts — ADR-0003 (budgets, repair-cursor
  self-healing, bounds-at-max EditableMesh trick).
- Shared config modules — ADR-0004.
- Boss/pet visuals client-side only; body morph + followers + pass perks
  replicate via player attributes (no remotes).
- Quests measure lifetime-stat DELTAS vs a daily baseline — zero hooks.
- Biome per cake = highest rebirth online (shared-cake compromise).
- Combo is FX-only (never calories) — no server combo validation surface.

## Studio verification (live playtest, 3 sessions)
Full loop demonstrated end-to-end: bites → craters + slump + glutton +
walkspeed penalty → gym prompt session → 1315 cal banked → upgrades bought
from the panel (costs resync) → tiny test cake eaten to 100% (auto-sweep)
→ Cake Guardian boss w/ HP bar → taps → PetRevealOverlay (odds footer) →
new cake spawns → pet equipped (inspector stats row) → follower orbits.
Persistence: economy v1→v2 migration ran; calories/pets survived restarts.
Fixed during verification: menu/gems-pill overlap, gym belly-HUD resync
after burn, swoosh.wav placeholder, TimeRewards/Social gold→gems, AppRoot
nil-clear bug (template bug! see QUEUE), list-cell zero-height collapse.

## Post-review hardening (adversarial pass: cake-sim / client / UI scopes)
CRITICAL fixed: **UnreliableRemoteEvent ~900-byte drop cap** — 2 KB delta
packets were silently discarded by the engine; now ≤150 cells + 40 repair
per packet, up to 3 packets/flush (verified live: 44 packets, no loss).
Also fixed: hole-punched-FIFO `#` misuse (explicit head/tail cursors);
settle re-queues the flowed cell (walls no longer freeze over-repose);
`SurfaceHeightAt` honest nil + rim samples no longer blend void zeros
(wrong-layer payouts at the rim); EatAt Y-surface anti-cheat implemented
(was dead config); first-cake-always-golden server-hop farm closed;
unloaded players can no longer consume finds; slump-loop peak-hold (was
starved to silence); touch aim GUI-inset mismatch; multi-touch no longer
cancels/hijacks eat-hold; prediction gated until the profile is live;
buy/claim/rebirth buttons got aspect-matched styles (rendered at 60%
height); AppRoot view-models memoized (bite-rate re-render storm);
gym tap counter keyed on session identity; "Next Biome" off-by-one;
pet bonuses capped at CURRENT slots (lapsed VIP kept 5); juice constants
moved to JuiceConfig; FloatingNumbers tweens pre-built; localized
Equip/Select strings; overflow warns in fixed-row panels; LocaleData
missing-key warn dedupe. Economy-scope reviewer died to API limits — a
manual pass covered spend/refund races (all spend-then-apply, no yields),
quest baseline math, boost expiry; queued for a re-run next session.

## Visual overhaul + collision (user feedback pass, 2026-07-17)
User verdict on v1 visuals: ugly + "постоянно в торте" (sinking). Reference
screenshots (keycap/butter-stick floors, candy-room walls) replicated:
- **Part grid is now THE renderer** (`render.forceFallback = true`): grooved
  glossy "keycap" columns (gap 0.35, per-layer `gloss`, deterministic shade
  jitter), juicier saturated layer palettes, butter-gold rare tint.
  EditableMesh path parked (vertex colors render white — open issue).
- **Collision fixed**: columns CanCollide/CanQuery → walking + bite raycasts
  match visuals 1:1; server grid 8×8 → 16×16 safety slabs; players standing
  in the footprint are lifted onto new cakes (were being buried alive).
- **Underfoot feel** (reference butter dents): squish ported to the part
  grid + walk-crunch (footstep-cadence layer SFX + crumb puffs).
- **Candy room** (MapService rebuild): studded chocolate walls + pink accent
  wall + X-braces, ~80 procedural candy props (gumballs/lollipops/mints/
  cookies/bars/cupcakes/strawberries/wraps), cotton-candy ceiling, dark
  chocolate floor, cream cake plate, peppermint candles, brighter warm
  lighting; default Baseplate/SpawnLocation removed at Build.
Verified in Studio over 3 play iterations (screenshots vs references).

## Cake 2.0 (user feedback pass 2, 2026-07-17): real cake, real bites
"Не кейкапы — торт": EditableMesh is now THE renderer and the strata are
real. What changed and the ENGINE GOTCHAS paid for it (all probe-verified):
- **Strata per pixel**: a 1×256 palette texture (EditableImage) sampled by
  height through per-vertex UVs — vertex colors would SMEAR layers across
  the tall skirt quads; the texture bands stay crisp on outer sides and
  crater walls. UV v maps rows directly (probe-calibrated, no flip).
- **Upvalue trap**: writePaletteImage was defined above the
  `local paletteImage` declaration → captured a global nil → silently
  never wrote → black cake. Locals must precede the functions that close
  over them.
- **LOD/bounds** (corrected 2026-07-17, see `2026-07-17_cake-grounding-fixes.md`):
  runtime-edited meshes need RenderFidelity=**Precise** — it has no LODs
  and renders live edits at any distance. **Automatic** swaps in LODs
  generated from CREATION-time content by distance/quality (stale mangled
  "canopy"). Either way the mesh is created at FULL height and NEVER
  flattened post-create (culling bounds come from creation geometry —
  flattening once made the cake vanish at distance).
- **Origin mapping** (2026-07-17): `CreateMeshPartAsync` parts render
  vertices at RAW mesh coordinates relative to `part.CFrame` — no
  bounding-box recentering; mesh y=0 lands at `part.Position.Y`. Position
  the part at the grid origin, not at origin + maxHeight/2 (that floated
  the cake 30 studs above the tray).
- **Closed skirt** (2026-07-17): boundary vertices average ONLY
  in-footprint cells, and faces exist for every cell whose 3×3
  neighborhood touches the footprint (same rule) — an analytic "+1 ring"
  rounded-rect test diverged at corner staircases and left full-height
  see-through slits. DoubleSided=true keeps flipping steep wall quads
  visible.
- **Two-pass rebuild**: normals read neighbor display heights; writing in
  one pass baked sideways normals → near-black top.
- Environment specular 1.0 made frosting mirror the dark room at grazing
  angles → 0.1.
- **Bite feel**: crater SNAPS instantly (target drops > snapDropStuds),
  server holds bitten cells for settleDelayAfterBite=0.7 s, then they ooze
  back at lerpSpeed 3.5 (moveFactor 0.35) — bite, pause, slow flow.
  Pooled ChunkDebris parts arc out of every bite.
- **Loaf footprint**: fixed rounded-rect 56×38 cells (84×57 studs, ~205k
  studs³ — Drain-the-Lake scale), replaces per-population round radius
  (GridUtil.InCake takes {hx,hz,corner}); crust band (lighter+glossier top
  0.8 studs) in the palette; collision columns stay invisible under the
  mesh (visible keycap mode remains the no-EditableMesh fallback).
- Diagnosis tip that cost an hour: a teleported third-person camera ends
  up INSIDE the mesh → backface culling hides everything → looks exactly
  like a rendering bug. Verify with a Scriptable camera from outside.

## Open Questions / Followups
- ~~Skirt "icing drip" spikes at the cake base~~ — resolved 2026-07-17
  (`2026-07-17_cake-grounding-fixes.md`): they were corner slits from the
  analytic ring test + candles clipping through the walls.
- Feel-tune settleDelayAfterBite / lerpSpeed / chunk velocities on device.
- **EditableMesh** is OFF for this experience — enable "Mesh & Image APIs"
  in Game Settings → Security to get the smooth renderer (fallback runs).
- Dashboard: create 9 dev products + 6 gamepasses, fill ids in ShopData;
  set SocialData.groupId.
- Replace placeholder rbxasset sounds with uploaded ASMR samples
  (JuiceConfig.sounds) and pet looks with real models (PetConfig.look).
- Adversarial-review findings fixed separately (see review section of this
  doc's follow-up flow if created) + upstream QUEUE rows captured (U1).
- Mobile MicroProfiler pass on a real phone (GDD §14) still pending.

## Related
- Features: cake-sim, cake-cycle, treasures, body-gym, upgrades, pets,
  rebirth, quests, juice, economy, app-root
- ADRs: 0003 (heightfield), 0004 (shared config)
- Prior flow: `2026-07-16_feature-library-batch.md`
