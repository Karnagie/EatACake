# Pets (rolls, collection, equip, followers)

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

## Files
`ProfileSchema/PetsSection`, `services/PetService`, `subscriptions/PetSubs`;
shared `config/PetConfig`; client `PetsSubsClient`, `PetFollowers`,
`LocalPetsService`, kit `PetRevealOverlay` + PetsInspectPanel.
