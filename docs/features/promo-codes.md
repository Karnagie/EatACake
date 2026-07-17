# Promo codes

## What it does
Code redemption with a per-player one-time ledger. Net-new for the template
(Dices never had it).

## Tuning
`src/server/data/CodesData.lua`: `codes[CODE] = { reward, expiresAt? }`
(keys pre-normalized: UPPER-CASE, no spaces — boot validation warns
otherwise), `maxLength`, `attemptCooldownSeconds`.

## State
Profile section `codes`: `redeemed = { [code: string] = true }`.

## Flow
`RedeemCode(raw)` → type/length guard + per-player cooldown (cooldown REPLIES
`{status="cooldown"}` — never silent) → `CodesService.Check` (peek:
invalid/expired/already/ok) + HasHandler pre-check (a code is never consumed
when its reward can't be granted) → `TryRedeem` marks the ledger →
`RewardGrantSubs.Grant` → Save → `CodeResultUpdate { status, granted? }`.
No yields between Check and grant — no eat-the-code race.

## UI
Kit `CodesPanel`: small centered dialog — `TextInput` (kit-styled TextBox,
clamped to 32 chars; keep in sync with `CodesData.maxLength`), green Redeem
button (enabled when non-empty), localized status line (green ok / red error).

## Files
Server: `CodesData`, `CodesSection`, `CodesService`, `CodesSubs`. Client:
`CodesSubsClient`, AppRoot panel. Remotes: `RedeemCode`, `CodeResultUpdate`.
