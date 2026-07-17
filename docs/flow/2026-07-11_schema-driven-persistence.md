# 2026-07-11: Schema-driven persistence (template foundation)

## Task
Start the reusable game template (RobloxTemplate) with a schema-driven
persistence layer, learning from the Dices codebase and its documented
mistakes.

## Context
New empty repo. Reference: Dices `PersistenceService` (hand-rolled DataStore,
4-copy field whitelist, no session locking/BindToClose/retries/migrations)
and its history: numeric-key stringification bugs, contract flags lost on
relog (Dices ADR-0009), legacy fields patched at load instead of migrated.

## Plan
Vendor ProfileStore (user-approved exception to the no-dependency rule);
define the profile as declarative per-feature section files
(`data/ProfileSchema/`); PersistenceService assembles the template and runs
migrate → reconcile → int-key normalize → sanitize per section on load.
Carry over the Dices bootstrap/architecture (R1–R7, Init/Start lifecycle).

## Changes

**Created:**
- `default.project.json`, `aftman.toml`, `.gitignore` — Rojo skeleton (mirrors Dices)
- `CLAUDE.md` — template constitution: Dices rules R1–R7/D1–D4 + new persistence rules P1–P5
- `src/shared/lib/ProfileStore.luau` — vendored verbatim (MAD STUDIO, Apache-2.0, 2243 lines)
- `src/server/ServerBootstrap.server.lua`, `src/client/LocalBootstrap.client.lua` — Dices bootstrap, improved: missing folders skipped gracefully
- `src/server/data/PlayerProfileData.lua` — runtime cache (`profiles` + `sessions`)
- `src/server/data/PersistenceData.lua` — store name, mock flag, kick messages
- `src/server/data/ProfileSchema/init.lua` — section registry; `_TEMPLATE.lua`; `CoreSection.lua` (player settings)
- `src/server/services/PersistenceService.lua` — load/save/unload + schema pipeline
- `src/server/subscriptions/PlayerLifecycleSubs.lua` — join/leave wiring, feature hooks
- `docs/` — MAP, feature doc, ADR-0001, recipe `add-profile-section.md`, registries, this flow

## Decisions
- **ProfileStore vendored, not reimplemented** — see ADR-0001. Autosave loop,
  BindToClose and retries deliberately absent from our code (inherited).
- **Per-section versioning + migrations** instead of store-name versioning.
  Adding a defaulted field requires nothing (reconcile); shape changes bump
  `version` + add `migrations[oldVersion]`.
- **`intKeySets` as a first-class schema concept** — kills the recurring
  Dices bug class (stringified numeric keys) declaratively.
- **`isNew` = `SessionLoadCount == 1`**, created-at = `FirstSessionTime` —
  native ProfileStore fields; preserves the Dices guarantee that a failed
  read never mis-tags a returning player as new (load failure = kick).
- **Sections removed from schema are preserved** in stored data (no silent wipes).
- Migration failure warns and continues (reconcile+sanitize as safety net)
  rather than blocking the profile.
- Post-review hardening (adversarial code review pass): `__schema` stamps
  never downgrade (old-server/new-server mixed fleet would corrupt data);
  warn when a version bump lacks a migration step; strict `^-?%d+$` match in
  int-key normalization (`tonumber` alone converts "1e5"/"nan" — NaN index
  errors); `applySchema` wrapped in pcall with EndSession+kick on failure
  (poisoned profile must not leak a session lock); `IsActive` re-check after
  connecting `OnSessionEnd` (signal doesn't replay); no kick with a false
  message on server shutdown (`ProfileStore.IsClosing`); `store == nil`
  guard in LoadProfile; dropped deprecated `Workspace.FilteringEnabled` from
  project.json.

## Open Questions / Followups
- Feature library next: daily/time/group rewards, shop, settings UI, promo
  codes, gamepasses — each as data+service+subs triad with its own section file.
- `Net.lua` + remotes/remoteUpdates folders when the first replicated feature lands.
- Localization toolchain (port `tools/robloxloc` from Dices) when player-facing
  strings appear; kick messages in `PersistenceData` should route through it.
- Consider selene + StyLua configs.
- Play-mode verification in Studio (Studio MCP): join/leave/save cycle, mock mode.

## Related
- Feature: `docs/features/persistence.md`
- ADRs touched: ADR-0001
- Prior flow: — (first task in repo)
