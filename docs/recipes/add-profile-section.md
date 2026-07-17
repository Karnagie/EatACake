# Recipe: add a profile section (persistent state for a feature)

Use this whenever a feature needs data that survives rejoins.

## Steps

1. **Copy the template.** Duplicate
   `src/server/data/ProfileSchema/_TEMPLATE.lua` →
   `src/server/data/ProfileSchema/<Feature>Section.lua` (PascalCase, no
   leading underscore).

2. **Fill the contract.**
   - `key` — unique top-level field, camelCase (e.g. `"dailyRewards"`).
     Check existing keys in `docs/registries/data-keys.md` first (D1).
   - `defaults` — the full shape with safe defaults.
   - `intKeySets` — list EVERY table keyed by numbers (e.g. claimed-by-level
     sets). Forgetting this reintroduces the classic stringified-keys bug (P3).
   - `version = 1`, empty `migrations`, `sanitize` only if values need
     coercion beyond "missing → default".

3. **Use it.** In the feature's service:
   `local profile = profileData.Get(userId)` →
   `profile.<key>.<field>` read/mutate directly. No save calls needed
   (auto-save); call `PersistenceService.Save(userId)` only after
   Robux-purchase grants.

4. **Push initial state to the client** (if the feature has UI) from
   `PlayerLifecycleSubs.onPlayerAdded` or the feature's own subs module.
   ⚠ RemoteEvents also stringify numeric keys — send arrays or re-normalize
   client-side.

5. **Document (D2).** Add the section key + fields to
   `docs/registries/data-keys.md`; update `docs/MAP.md`.

## Changing an existing section later

- **Adding a field:** just add it to `defaults`. Reconcile fills it on next
  load. No version bump needed.
- **Renaming / restructuring / changing meaning:** bump `version`, add
  `migrations[oldVersion] = function(section) ... return section end`.
  Migrations run before reconcile, so old fields are intact inside them.
- **Removing a section file:** stored data for it is preserved untouched
  (safe), it just stops being reconciled/migrated.

## Never

- Add profile fields outside `ProfileSchema/` (P1)
- Touch `DataStoreService` directly (P5)
- Store Instances, functions, mixed arrays/dicts, or non-UTF8 strings in a
  profile (DataStore JSON cannot encode them)
