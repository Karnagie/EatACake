# Recipe: start a new game from the template

1. Create the game as a git clone (NOT a plain folder copy) so template
   improvements can be pulled down later via git instead of manual diffing:
   ```
   git clone D:\Projects\Roblox\RobloxTemplate D:\Projects\Roblox\<GameName>
   cd D:\Projects\Roblox\<GameName>
   git remote rename origin template
   ```
   Later, to pull template improvements down:
   `git fetch template` → review `TEMPLATE_CHANGELOG.md` entries newer than
   the clone point → `git cherry-pick` (or merge) the wanted commits —
   ALWAYS reviewing the diff; never bulk-overwrite game files.
   (Fallback if the template isn't a git repo yet: plain copy + `git init`;
   pull-down then degrades to manual diffing by changelog.)
2. In the clone:
   - `default.project.json`: `"name"` → the game name
   - `README.md`: retitle; keep the Status list, it becomes the game's
   - `TEMPLATE_CHANGELOG.md`: KEEP — records which template baseline this
     game started from
   - `docs/upstream/QUEUE.md`: keep the header, it must start with zero rows
   - `docs/flow/`: keep INDEX + files — they stay valid history of inherited
     code
   - commit: `git commit -m "start <GameName> from template"`
3. Tune per game: ProfileSchema section defaults (starting gold...),
   `DailyRewardsData.days`, `PersistenceData` messages.
4. Author the UI in Studio per each feature doc's GUI contract
   (`docs/features/*.md`), `ResetOnSpawn = false`.
5. `aftman install`, `rojo serve`, playtest — the console must match the R8
   healthy-boot contract (see `.claude/agents/studio-verifier.md`).
6. CLAUDE.md is NOT edited: it governs games and template alike, including
   the Self-Improvement Loop (U1–U4) that flows discoveries back to
   `D:\Projects\Roblox\RobloxTemplate`.
