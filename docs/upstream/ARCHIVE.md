# Upstream archive — settled candidates

> Where a queue row goes when it is DONE. `QUEUE.md` holds pending rows only;
> without this file the depth signal in U1b can never fall and the queue grows
> forever — which is exactly what happened here (200 rows captured between
> 2026-07-12 and 2026-08-02, none ever settled).
>
> Rows are moved here **by ID**, carrying:
> `harvested <date> <sha>` — the sha is the template commit that carries it
> (one commit per candidate, U3) — or `rejected: <reason>`.
>
> **Rejections stay here permanently**, so a future harvest cannot
> re-litigate them. `grep` here before proposing anything.

| ID | Date | Type | P | Claim + detail | Evidence | Outcome |
|---|---|---|---|---|---|---|
| EAC-0024 | 2026-07-16 | contract | P1 | Shared per-player rate limiter for resync-answering remotes (Claim*/Request* reply with full payloads on invalid input — amplification) | Review finding #11 of feature-library batch; codes/group have cooldowns, daily/time/shop don't | harvested 2026-08-03 c3e5d43 (TPL-0001) — RateLimitService + RateLimitData wired into all six resync-answering handlers |
| EAC-0025 | 2026-07-16 | contract | P1 | jsdotlua useEffect deps must never contain nil — add to roblox-ui-kit skill pitfalls | Feature-library review CRITICAL #3: `{ nil }` has length 0, positional deps compare never re-runs the effect; cost a dead countdown ticker | harvested 2026-08-03 c3e5d43 (TPL-0002) — jsdotlua nil-in-deps pitfall added to the roblox-ui-kit skill |
| EAC-0026 | 2026-07-16 | fix | P1 | **AppRoot.Set cannot clear fields**: `Set({ openPanel = nil })` is a silent no-op (`pairs` skips nils) — every panel close/toggle in the template is broken. Fix: `AppRoot.Open(panel?)` assigns directly + new `AppRoot.Clear(key)`; onClose/toggle call them; CodesSubsClient `Set({codesStatus=nil})` too | EatACake: found in Studio verification (panels would not close); fixed in `modules/AppRoot.lua`, `subscriptions/CodesSubsClient.lua` | harvested 2026-08-03 c3e5d43 (TPL-0006) — AppRoot.Clear/Open/Get; every panel close site rewritten |
| EAC-0052 | 2026-07-18 | fix | P1 | ProcessReceipt not idempotent for CONSUMABLE dev products — only oneTime items dedup (IsOneTimeOwned), no PurchaseId ledger → Roblox receipt re-delivery double-grants gems/pets | EatACake ShopSubs.processReceipt; template feature-library shop. Fix: persisted bounded PurchaseId FIFO section, check before grant, gate on ProfileStore LastSavedData | harvested 2026-08-03 c3e5d43 (TPL-0007) — bounded purchaseLedger array + SaveAndWait + NotProcessedYet |
| EAC-0053 | 2026-07-18 | fix | P1 | Net.Remote/Net.Update use WaitForChild with NO timeout — a missing/renamed remote yields forever inside a subscription Start(); the pcall'd bootstrap loop yields with it, later subs never wire, only engine "Infinite yield" (not Log-routed) | EatACake Net.lua; core template infra. Fix: bounded WaitForChild + Log.Warn/GraceOnce, or a boot-time resolver returning a nil-safe stub | harvested 2026-08-03 c3e5d43 (TPL-0005) — bounded waits, nil-safe stub, Net.IsStub |
| EAC-0201 | 2026-08-02 | fix | P1 | **Mixed CRLF/LF in a repo file makes a script silently process a fraction of it and report success.** `QUEUE.md` carried 5 CRLF among 210 LF. A backfill script that picked its separator by testing whether the file contained a CRLF sequence split 216 lines into 6 chunks, touched 5 rows of 200, and printed a clean summary. Split on the LF and preserve each line's own CR. Root cause was a missing `.gitattributes`; mixed endings also break multi-line exact-match edits while single-line matches still succeed, so the failure reads as random. | this repo | harvested 2026-08-03 f340a30 (TPL-0018) — `.gitattributes` added upstream |

> **Note on the other ~197 rows.** They stayed `pending` on purpose. They fed
> SYNTHESES in the template — `docs/reference/roblox-engine-gotchas.md`, the
> roblox-ui-kit skill, `tools/` — where no single row was *the* source. Marking
> them harvested would overstate what landed; the next harvest re-triages them
> against what the template now already has.
