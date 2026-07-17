# Eat A Cake

*At a cake factory, your pet fell into a giant cake — eat the whole cake to
rescue it.* A mobile-first "eat the map" simulator built on the
RobloxTemplate architecture (GDD: granular heightfield cake, GDD v1).

Start here: `CLAUDE.md`, then `docs/MAP.md`.

## Getting started

```sh
aftman install
rojo serve   # connect from Roblox Studio via the Rojo plugin
```

For the smooth cake renderer, enable **Mesh & Image APIs** in
Game Settings → Security (otherwise the part-grid fallback is used).

## The game (v1)

- [x] Granular heightfield cake: wide bites, angle-of-repose slumping,
      per-layer physics/visuals (frosting/sponge/chocolate/jelly/cotton/
      caramel/crumb), auto-sweep (ADR-0003)
- [x] One shared cake per server: 12 Hz buffer deltas (unreliable +
      self-healing repair cursor), client bite prediction, EditableMesh
      renderer + part-grid fallback, 8×8 collision
- [x] Loop: eat → belly fills (glutton x2 at full, −40% speed) → gym mash
      minigame burns fat into calories → 6 upgrades → cake bottom → Cake
      Guardian boss → free server-seeded pet roll for everyone → new cake
- [x] Pets (6 rarities, odds in UI, dup-merge levels, followers), rebirth
      ("Food Coma", +25%/level, biome unlocks), treasures buried in the
      cake, daily quests, streak/time rewards, promo codes, leaderstats
- [x] Monetization: 6 gamepasses + 9 dev products (ids pending dashboard)
- [x] ASMR juice layer: pooled sounds/particles/floating numbers, combo,
      camera shake, crust crack, underfoot squish, body morph
- [ ] Dashboard ids (dev products / gamepasses / groupId)
- [ ] Uploaded ASMR sound set + real pet models (placeholders wired)
- [ ] MicroProfiler pass on a real phone (GDD §14)

## Template

Built from RobloxTemplate (`D:\Projects\Roblox\RobloxTemplate`); template
improvements discovered here flow back via `docs/upstream/QUEUE.md` (U1-U3).
