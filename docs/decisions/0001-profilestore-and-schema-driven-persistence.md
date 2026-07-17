# ADR-0001: ProfileStore + schema-driven profile sections

## Status
Accepted (2026-07-11)

## Context
The predecessor codebase (Dices) used a hand-rolled persistence layer:
`GetAsync`/`SetAsync` without session locking, retries or `BindToClose`, and a
profile whose field list was maintained by hand in **four** places
(defaults, load-copy whitelist, save-payload whitelist, sanitize). Documented
consequences: fields silently not persisting when one copy was missed
(contracts `completed` flag lost on relog — Dices ADR-0009), recurring
numeric-key stringification bugs (`claimedRewards`, `timeClaimed`), no
migration mechanism beyond the store name suffix, data-loss exposure on
shutdown and on fast rejoin (last-write-wins).

## Decision
1. **Vendor ProfileStore** (MAD STUDIO / loleris, Apache-2.0) as
   `src/shared/lib/ProfileStore.luau` — the community-standard,
   battle-tested solution for session locking, periodic auto-save, retries,
   shutdown handling and dupe prevention. Vendored (not a package manager
   dependency) to keep the template dependency-free at the toolchain level;
   the file is treated as read-only. The "no external frameworks" rule gets
   this single, deliberate exception because persistence is the highest-risk
   place to hand-roll.
2. **Schema-driven sections.** Each feature declares its slice of the profile
   in one file under `data/ProfileSchema/`: `key`, `version`, `defaults`,
   `intKeySets`, `migrations`, `sanitize`. `PersistenceService` assembles the
   template and runs migrate → reconcile → int-key normalize → sanitize on
   load. Numeric-key stringification — the most frequent historical bug — is
   handled declaratively (`intKeySets`).

## Alternatives considered
- **Keep hand-rolled layer, add locking/retries**: highest-risk code to get
  wrong; reinventing a solved problem.
- **Wally + ProfileStore package**: adds a package manager to the toolchain
  for a single dependency; vendoring is simpler for a template.
- **Central Schema.lua**: one file all features edit; conflicts with the
  drop-in feature-library goal (a feature = self-contained files copied in).

## Consequences
- `PlayerLifecycleSubs` contains **no** autosave loop, no `BindToClose`, no
  retry logic — reimplementing them on top of ProfileStore would be a bug.
- `isNew` comes from `Profile.SessionLoadCount == 1`; created-at from
  `Profile.FirstSessionTime` (not stored in sections).
- Lock conflict kicks the player (messages in `PersistenceData`).
- Store name is stable ("PlayerProfiles"); versioning is per-section.
- License note: Apache-2.0 header preserved inside the vendored file.
- **R4 exemption:** ProfileStore's internal signals (`OnSessionEnd`,
  `OnError`) are connected inside `PersistenceService`, not in subs — they
  are library lifecycle plumbing, not game events. Documented in CLAUDE.md R4.
- **`__schema` stamps never downgrade** (`math.max(storedVersion, current)`):
  after publishing an update, old servers keep running; an old server must
  not re-stamp a lower version onto data a new server already migrated
  (migrations would re-run and corrupt it).
- Known upstream quirk: `ProfileStore.Mock:StartSessionAsync` ignores the
  `params` (`Cancel`) argument. Only affects `useMockInStudio = true`;
  contained by the player-left re-check after load. Vendored file stays
  unmodified (matches upstream `main` byte-for-byte).
