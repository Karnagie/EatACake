# Pets — displayed as SQUISHIES (rolls, collection, equip, followers)

## Naming: display-only
Players see "Squishies" (squishy toys shaped like food). The module names, the
remotes (`EquipPet`, `PetsUpdate`, `PetRollUpdate`), the profile section `pets`
and every `PetConfig` **`id`** keep the pet-* naming ON PURPOSE: an `id` is a
DataStore key inside `pets.owned`, so renaming one orphans a collection, and the
per-section `migrations` table cannot express a cross-section key rename. The
re-theme edits ONLY the right-hand side of `LocaleData`.
**Adding a new id is safe and needs no migration** (it is simply absent from
everyone's `owned` map) — that is how the roster grew 12 → 30 at `PetsSection`
v1. Renaming or removing one is not: that needs `version += 1` + `migrations`.

## What it does
GDD §9: every cake cycle ends with ONE free random pet per player; eggs
(cycle/lucky/mega/epic7) are the reward kind `egg`. ⚠ Only `cycle` (the cake/boss
roll) and `epic7` (daily day 7) are granted by anything since 2026-07-31 — the
Lucky/Mega egg products were removed from the shop; their odds tables stay in
`PetConfig.eggs`, unsold. Rolls happen ONLY in
`PetService.Roll` on the server; odds live in `Shared/config/PetConfig` and
the SAME table renders in the UI (odds disclosure — Roblox policy).

## State
Profile section `pets`: `owned {petId = copies}` (copies = level, dup merge
is automatic), `equipped` (3 base slots, 5 VIP via `StatsService.PetSlots`).
The equip cap is enforced at equip time against the CURRENT slot count, but the
persisted `equipped` array can EXCEED it after a VIP lapse — StatsService pays
out only the first `slots` entries. Bonuses (calories/eatSpeed/gems %) aggregate
over equipped pets × `(1 + mergeBonusPerCopy × (copies-1))` inside StatsService.

## Roll = Preview + Grant (2026-07-30)
`PetService.Roll` mutates the collection, so it cannot be used to SHOW a prize
before it is won. It is now two halves:
- **`Preview(userId, eggType?, minRarity?)`** — decides `{petId, rarity}`, mutates
  nothing (a `minRarity` floor zeroes every rarity below it, as before);
- **`Grant(userId, petId)`** — adds that specific id, returns
  `{petId, rarity, copies, isNew}`;
- **`Roll` = Preview + Grant**, so every existing caller is untouched.

This is what lets the boss fight advertise the squishy at stake and then commit
exactly that one on a win (`features/cake-cycle.md`). Any reward that should be
visible before it is earned uses the split; anything revealed at the moment of
winning keeps using `Roll`.

## Where the panel opens
The lobby's meta menu, **and** the game HUD's own menu since 2026-08-13
(`features/app-root.md`) — so a squishy can be equipped mid-run. This needed no
new wiring: `PetSubs`, `PetsSubsClient`, `LocalPetsService` and the panel are all
COMMON, and `PetsSubsClient` already owns the follower step in BOTH places. The
equip round-trip is `EquipPet` → validate → `PetsUpdate` + the `EquippedPets`
attribute, so the follower changes in the same push.
⚠ `slots` is a GAMEPASS perk on a PUSHED snapshot — a VIP bought mid-run used to
leave the panel showing "3 / 3" until the next place transition. It is re-pushed
now (`features/shop.md`, Gamepasses).

## Flow
- Cycle reward / `egg` grants → `PetRollUpdate {petId, rarity, copies,
  isNew, source}` (reveal UI) + `PetsUpdate {collection, slots}`.
- ⚠ Boss phase used to ADVERTISE the prize (`pendingPet` per player →
  `BuildPrize` → `BossPrizeCard`). REMOVED 2026-08-07 by request — what a cleared
  cake pays is a surprise again. `PetService.Preview`/`Grant` stay split (`Roll`
  is built from them); there is simply no second caller.
- `EquipPet` remote (petId, equip) → PetService validate → `PetsUpdate`.
- Followers: server writes attribute `EquippedPets` = csv petIds; every
  client renders primitive followers locally (`PetFollowers`, R5 templates).

## Rarity mapping (UI)
config ids `common..secret` → Theme.Rarity keys `Common, Uncommon, Rare,
Epic, Legendary, Secret` (Uncommon/Secret added to the kit for this game).
Colour lives ONLY in `Theme.Rarity` — `PetConfig.rarities[].color` was a second,
disagreeing palette with zero consumers and was deleted.
`Common` is warm foam cream (it used to alias `Theme.Button`, making a Common
card identical to every button in the kit; a cool grey was rejected because it
collides with the hex tree's locked state). `Secret` is violet-void, −42° off
Epic magenta, which it was only 11.9° from. Each tier also carries `Outline`,
`Text`, `IconDisc` and `IconStar`.

## Art
Each `PetConfig` entry names an `icon` (a `Theme.Icons` key, e.g. `SqCookie`)
explicitly rather than deriving it from the id, so a typo warns via
`Theme.Icon` instead of silently rendering the fallback glyph. The icon flows
through `LocalPetsService` → `PetCard.iconName` / inspector plate / reveal
overlay. The reveal shows art only once the spin LANDS — showing the prize
mid-spin spoils it. `PetFollowers` still uses the primitive `look` until real 3D
models land.

## Gotchas
- **Follower yaw offset is `-90`, not 180.** The authored art puts the face on
  the model's **-X**, not on +Z as the old note assumed: `CFrame.lookAt` sends
  local -Z down the travel direction, and under the old 180° offset the axis that
  ended up on that frame's +X — what players read as "facing right" — was -X.
  One number fixes both poses, because `PetFollowers` builds its yaw as
  `yawOffsetDegrees + 180 * (1 - facing)`, so the moving pose and the idle
  swivel-to-look-at-you both ride it. If it ever comes out mirrored, +90 is the
  only other root — a sign flip, never a new number. Derivation in
  `PetConfig.follow`.

## Files
`ProfileSchema/PetsSection`, `services/PetService`, `subscriptions/PetSubs`;
shared `config/PetConfig`; client `PetsSubsClient`, `PetFollowers`,
`LocalPetsService`, kit `PetRevealOverlay` + PetsInspectPanel.
