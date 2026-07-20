# Overnight audit — findings report (2026-07-18)

> From the adversarial review (Package A): 11 subsystems reviewed vs R1-R8 /
> P1-P5 + bug classes, each finding skeptic-verified. 45 raw → **11 confirmed**
> + **2 plausible** (survived verification; the 5-hour limit cut 28 of the
> verify agents short, so a few more raw findings went un-adjudicated — re-run
> after reset to close that gap). Branch `auto/2026-07-18-overnight-hardening`.
>
> Legend: ✅ FIXED this run · 🕵 NEEDS YOUR DECISION (design/runtime) · 📄 doc.

---

## 🔴 CRITICAL — money path (NOT auto-fixed; needs your call)

### 1. 🕵 ProcessReceipt is not idempotent for consumable dev products → Robux dup
`ShopSubs.lua` `processReceipt` (169-211) grants, Saves, returns
`PurchaseGranted` — but never records `receiptInfo.PurchaseId`. The ONLY dedup
is the `oneTime` path (`IsOneTimeOwned`, 193). Every consumable — gem packs
`gems-s/m/l/xl`, `lucky-egg`, `mega-egg`, `instant-burn`, `boost-15m` — has NO
dedup. Roblox re-invokes ProcessReceipt for the same purchase when a prior
`PurchaseGranted` didn't reach it before the server closed → **second grant for
one purchase** (double gems / a second pet roll). The vendored ProfileStore
(`ProfileStore.luau:99`) even documents `Profile.LastSavedData` as the intended
receipt-handling mechanism, unused here.
**Why not auto-fixed:** the fix needs a NEW persisted `PurchaseId` ledger — a
ProfileSchema section (P1) with a version stamp, `intKeySets` if numeric (P3),
and ideally gating on `LastSavedData`. That's a schema/design decision + a
`studio-verifier` play-test, both yours to make.
**Fix sketch:** persist a bounded FIFO of processed PurchaseIds (e.g. last ~50)
in a profile section; at the top of `processReceipt`, if the PurchaseId is
already recorded return `PurchaseGranted` WITHOUT granting; else grant + record
in the same mutation + Save.

---

## 🟠 WARN

### 2. 🕵 grantableList under-validates boost/egg → bundle partial-delivery + permanent one-time lock
`ShopSubs.lua` `grantableList` (129-143) checks only `HasHandler(kind)` (plus a
DEAD `kind=="gold"` amount guard — see #12). It does NOT verify that a boost's
`boostId` exists in `treasureCfg.boosts`. If it drifts (boost ids live in
`TreasureConfig`, a separate module), `GrantBoost` returns false mid-loop;
`grantProduct` (156-166) only `Log.Warn`s ("Should be impossible…" — it isn't),
still `MarkOneTimePurchased`, and returns `PurchaseGranted`. For `starterpack`
(oneTime, gems+boost+egg) the player pays 99 R$, gets gems+egg but not the
boost, and can NEVER repurchase. Contradicts the `shop.md` "ALL-OR-NOTHING"
guarantee. (Verifier note: the egg leg is WRONG — `PetService.Roll` falls back
to the cycle egg for a bad `eggType`, so a typo yields a wrong-pool pet, not a
decline. Boost leg is real. **No live loss today** — `boost-15m` currently
exists in TreasureConfig — this is latent/drift-triggered.)
**Fix:** validate kind-specific preconditions in `grantableList` (boostId in
`treasureCfg.boosts`), and/or make `grantProduct` treat any nil grant as a hard
failure BEFORE marking oneTime — but only PAIRED with #1's PurchaseId dedup, or
a `NotProcessedYet` after a partial grant re-mints the succeeded grants on retry.

### 3. ✅ Silent early-return on the money path (offline payer) — R8 — FIXED
`ShopSubs.lua:180`: when the payer isn't in this server, returned
`NotProcessedYet` with no Log, while every sibling branch logs. Added
`Log.Once(SCOPE, receipt-offline-{userId}, …)`.

### 4. ✅ EquipPet drops the request silently when profile not loaded — R8 — FIXED
`PetSubs.lua:69`. Added `Log.Once(SCOPE, equip-preload-{userId}, …)`.

### 5. ✅ BuyUpgrade / ClaimQuest / DoRebirth drop silently pre-load — R8 — FIXED
`UpgradeSubs.lua:46`, `QuestsSubs.lua:44`, `RebirthSubs.lua:43`. Added
`Log.Once` per handler, mirroring the `CakeSubs` `eat-preload` pattern.

### 6. 🕵 Net.Remote/Net.Update use `WaitForChild` with NO timeout — R8 hang risk
`Net.lua:32,37`. A missing/renamed `.model.json` (or a typo in `Net.Remote("…")`)
makes `WaitForChild` yield forever. Subscriptions resolve remotes inside
`Start()`, run under `pcall` in the bootstrap loop — which YIELDS with it, so the
whole subscription phase stalls: later subs never start, the final `Log.Sum`
"complete" never prints, and the only signal is the engine's generic "Infinite
yield possible" (not routed through `Log`). R8 forbids blocking waits in flow.
**Why not auto-fixed:** touches the core resolver used everywhere; the right fix
(bounded `WaitForChild` + `Log.Warn`/`GraceOnce`, or a boot-time resolver that
logs each hit/miss and returns a nil-safe stub) is a small design choice worth
your eyes. **Strong template-upstream candidate** (queued).

---

## 🟡 INFO / robustness

### 7. 🕵 PetFollowers builds view templates with `Instance.new` (R5)
`PetFollowers.lua:28` — per-follower `:Clone()` is fine, but the source templates
are runtime-built, not authored in ReplicatedStorage. Header comment claims
"(R5)". Also `rebuild()` indexes `def.look.shape/color` unguarded — a future pet
without `look` would throw in RenderStepped. Self-documented placeholder; guard
`def.look` at minimum.

### 8. 🕵 VIP-lapse: follower count / "N/slots" show all persisted equips (needs_runtime)
`PetSubs.SendPets:40` emits every `equipped` entry to the `EquippedPets`
attribute; `StatsService.petBonus` pays only the first `slots`. After a VIP
lapse (or a join-window race where `RefreshPassOwnership` hasn't resolved) a
player sees 5 followers / "5/3" while only 3 pay out. Cosmetic, not dup. Cap the
emitted list + Collection's `equipped` flag at `PetSlots`. (Now noted in
`pets.md`.)

### 9. 🕵 UpgradesSection.sanitize can error on corrupt `levels`
`UpgradesSection.lua:23` iterates `pairs(section.levels)` with no non-table
guard — `QuestsSection`/`PetsSection` both guard theirs. A non-table `levels`
(external corruption / bad future migration) survives `deepReconcile`, throws in
sanitize (swallowed by pcall), then breaks every `BuyUpgrade`. One-line fix:
`if type(section.levels) ~= "table" then section.levels = {} end`. Low-risk but
a schema file — left for your nod (or say the word and I apply it).

### 10. 🕵 Codes panel status line not cleared on menu-toggle/panel-switch close
`AppRoot.lua:724` — only the X button clears `codesStatus`; closing via the menu
button or opening another panel leaves the stale status mounted. Clear it in
`AppRoot.Open` when the outgoing panel was "Codes".

### 11. 📄 MapService builds the whole room with `Instance.new` (R5 deviation)
`MapService.lua:39` — knowing, documented, working deviation (code-built map).
Flagged only so R5 status is explicit; consider an ADR exempting the code-built
map, or clone a template when a Studio scene exists.

### 12. 🕵 Dead `kind == "gold"` guards (corroborated by the doc-drift audit)
`ShopSubs.lua:138` & `GroupRewardSubs.lua:139` gate an amount check on the
phantom kind `"gold"` (real kinds: calories/gems/boost/burn/egg). The intended
"reject amount ≤ 0" pre-validation never fires for the real currency (`gems`).
Rename the guards to `"gems"` (or drop them if the gems handler's own check
suffices). Doc/comment already fixed (`DailyRewardsData.lua:8`); `shop.md`
money-path line intentionally left to update WITH this code fix.

---

## 🔵 PLAUSIBLE (verify after limit reset)

### P1. 🕵 Promo code consumed before grant confirmed → declining reward eats a one-time redemption
`CodesSubs.lua:57` — `TryRedeem` marks `codes.redeemed[code]=true` (+Save) BEFORE
`RewardGrantSubs.Grant`; the pre-guard only checks `HasHandler`, not that the
args actually grant (gems `amount<=0`, or a bad `boostId`). On decline the code
is spent, status still reports `ok` with `granted=nil`. Same class as #2 — grant
BEFORE consuming, or validate args in the pre-guard.

### P2. 🕵 PetService.Roll nil-deref when a weighted rarity set has no pets
`PetService.lua:94` — if a rarity bucket rolls but has no eligible pets, the
follow-up indexing can nil-deref. Verify the specific path after reset.

---

## Applied this run
- ✅ 5 R8 log-only fixes (#3, #4, #5) across ShopSubs/PetSubs/UpgradeSubs/
  QuestsSubs/RebirthSubs — purely additive `Log.Once`, build-verified.
- 📄 21 doc-drift fixes (Package C) across 13 feature docs + MAP + 2 code
  comments — see the worklog.

## NOT applied (need your decision / a play-test)
#1, #2, #6, #7, #8, #9, #10, #12, P1, P2 — money-path design, schema sections,
core-resolver change, or runtime verification. Each has a fix sketch above.
