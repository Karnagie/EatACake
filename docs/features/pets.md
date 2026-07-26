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
(cycle/lucky/mega/epic7) are the reward kind `egg`. Rolls happen ONLY in
`PetService.Roll` on the server; odds live in `Shared/config/PetConfig` and
the SAME table renders in the UI (odds disclosure — Roblox policy).

## State
Profile section `pets`: `owned {petId = copies}` (copies = level, dup merge
is automatic), `equipped` (3 base slots, 5 VIP via `StatsService.PetSlots`).
The equip cap is enforced at equip time against the CURRENT slot count, but the
persisted `equipped` array can EXCEED it after a VIP lapse — StatsService pays
out only the first `slots` entries. Bonuses (calories/eatSpeed/gems %) aggregate
over equipped pets × `(1 + mergeBonusPerCopy × (copies-1))` inside StatsService.

## Flow
- Cycle reward / `egg` grants → `PetRollUpdate {petId, rarity, copies,
  isNew, source}` (reveal UI) + `PetsUpdate {collection, slots}`.
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

## Files
`ProfileSchema/PetsSection`, `services/PetService`, `subscriptions/PetSubs`;
shared `config/PetConfig`; client `PetsSubsClient`, `PetFollowers`,
`LocalPetsService`, kit `PetRevealOverlay` + PetsInspectPanel.
