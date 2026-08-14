# RobloxTemplate — AI Context Document

> Source of truth for any AI agent working on this codebase.
> Read this file **first**. Then read `docs/MAP.md`. Then proceed.

This is a **reusable game template**: framework skeleton + drop-in feature
library. Game-specific content (theme, copy, gameplay) is added per project on
top of it. New games are created by COPYING this repo
(`docs/recipes/new-project-from-template.md`); this document governs both the
template and every copy — including the Self-Improvement Loop below, which
flows improvements discovered in games back into the template.

---

## Tech Stack

- **Engine:** Roblox (Luau)
- **Build tool:** Rojo 7.7.0 (via aftman)
- **Project file:** `default.project.json`
- **No external frameworks.** Custom lightweight architecture. The single
  vendored library is `src/shared/lib/ProfileStore.luau` (Apache-2.0, MAD
  STUDIO) — see ADR-0001. Never modify vendored files.

---

## Project Structure

```
src/
├── client/                        → StarterPlayer.StarterPlayerScripts.Client
│   ├── LocalBootstrap.client.lua  — entry point
│   ├── data/                      — client-side data modules
│   ├── modules/                   — client-side services (logic only)
│   └── subscriptions/             — client event subscriptions (split by domain)
├── server/                        → ServerScriptService.Server
│   ├── ServerBootstrap.server.lua — entry point
│   ├── data/                      — server-side data modules
│   │   └── ProfileSchema/         — profile section files (persistence schema)
│   ├── services/                  — server-side services (logic only)
│   └── subscriptions/             — server event subscriptions (split by domain)
├── shared/                        → ReplicatedStorage.Shared
│   ├── lib/                       — vendored libraries (ProfileStore)
│   ├── remotes/                   — RemoteEvents (client → server), .model.json
│   └── remoteUpdates/             — RemoteEvents (server → client), .model.json

docs/
├── MAP.md                         — ROUTING INDEX: one line per feature (read every task)
├── features/                      — one file per feature (the single source for that feature)
├── flow/                          — task history: INDEX.md (one line per task) + one file per task
├── recipes/                       — how-to guides for repeating patterns
├── registries/                    — uniqueness indexes ONLY (name -> owner + doc link)
└── decisions/                     — ADRs (architecture decision records)
```

---

## Architecture

### Bootstrap Flow

Both client and server follow the same initialization sequence:

1. **Load data modules** from `data/` (dynamic `require` via folder children)
2. **Load services** from `services/` (client: `modules/`)
3. **Load subscriptions** from `subscriptions/`
4. **Call `Init()`** on each data module (if defined)
5. **Call `Init(data)`** on each service
6. **Call `Start(data, services)`** on each subscription module

Modules are initialized in alphabetical order. Missing folders are skipped.

### Data Modules

- Store ALL game state and configuration. **No data lives outside data modules.**
- Expose config as table properties with kebab-case string keys
- May implement `Init()` for lazy initialization

### Services

- Contain ONLY logic. **NO data, NO constants, NO config.**
- Implement `Init(data)` to receive data modules
- Single responsibility per service

### Subscriptions

- One file per **domain** (e.g. `PlayerLifecycleSubs.lua`, `ShopSubs.lua`)
- Implement `Start(data, services)`
- **The ONLY place where event subscriptions happen** (PlayerAdded,
  OnServerEvent, UI .Connect, etc.)
- If a subscription file exceeds ~300 lines, split it by sub-domain.

### Client/Server Communication

- **Remotes** (`src/shared/remotes/`): client → server (RemoteEvents)
- **RemoteUpdates** (`src/shared/remoteUpdates/`): server → client (RemoteEvents)
- Defined as `.model.json` files, resolved at runtime via `ReplicatedStorage.Shared`
- ⚠ RemoteEvent serialization stringifies numeric table keys — send arrays,
  or re-normalize on the client.

---

## Persistence (schema-driven) — PERMANENT RULES

Player data is handled by `PersistenceService` on top of vendored
**ProfileStore** (session locking, auto-save every ~300s (first ~150s after load skipped), retries, final save
on shutdown — all inherited, never reimplemented). Full doc:
`docs/features/persistence.md`, ADR-0001.

### P1: Profile fields are defined ONLY in ProfileSchema sections
Every top-level slice of the profile is one file in
`src/server/data/ProfileSchema/` declaring `key`, `version`, `defaults`,
`intKeySets`, `migrations`, `sanitize`. Define a field once — it persists.
**Never** add profile fields anywhere else; there are no save/load whitelists
to update. Recipe: `docs/recipes/add-profile-section.md`.

### P2: Changing a section's shape requires a version bump + migration
Adding a new field with a default needs **nothing** (reconcile fills it).
Renaming/restructuring requires `version += 1` and a `migrations[oldVersion]`
function.

### P3: Number-keyed tables must be declared in `intKeySets`
DataStore JSON turns numeric keys into strings. Any `{ [n: number] = ... }`
table in a section MUST be listed in that section's `intKeySets` so it is
normalized back on load.

### P4: Access profiles through PlayerProfileData
Services read/mutate `PlayerProfileData.profiles[userId]` (equivalently
`.Get(userId)`) directly — changes auto-save while the session is active.
Do not keep references to profile tables across yields tied to a player who
may leave; re-fetch via `.Get(userId)` and handle nil.

### P5: Never bypass the session
No direct `DataStoreService` usage anywhere else on the codebase. No
`Steal = true`. Critical moments (Robux purchases) call
`PersistenceService.Save(userId)` right after mutating; grant purchases only
after checking the profile is loaded (`IsLoaded`).
**Sole exemption (ADR-0022):** `GlobalLeaderboardService` owns the
`OrderedDataStore`s behind the in-world leaderboards — cross-server RANKING has
no ProfileStore answer. No profile data lives there: the stores are a
write-only projection of three profile numbers, keyed by userId, never read back
into a profile. Any other module reaching for `DataStoreService` is still a bug.

---

## UI Workflow

**Kit-first.** All player-facing game UI (panels, HUD, shop, settings,
inventory, popups) is built from the ReactRoblox UI kit
(`ReplicatedStorage.Shared.UIKit`) following the MANDATORY skill
`.claude/skills/roblox-ui-kit/SKILL.md` (style rules, component catalog,
patterns, Studio verification checklist). Integration contract:
`docs/features/ui-kit.md`. Never hand-roll UI from raw Frames outside the kit.

For bespoke non-kit visuals (world-space UI, one-off Studio-authored screens):
visual layout is made by a human in Studio or via the Studio MCP — do NOT
hand-write large `.model.json` GUI trees; behavior is authored in code; the
contract is the **named instance tree** (code resolves children by exact
name, `UiData` resolver).

---

## Strict Rules — Code

These rules are **non-negotiable**.

### R1: Data belongs in data modules only
All state and config in `data/`. Never in services or subscriptions.

### R2: Services contain only logic
No constants, no config values, no state. Services get values from data
modules via `Init(data)`.

### R3: Services cannot use other services
Services may depend only on data modules. Cross-service calls are
**forbidden**. Coordinate via subscriptions:

```lua
-- ShopSubs.lua (correct — orchestrate in subscription)
Remotes.BuyItem.OnServerEvent:Connect(function(player, itemId)
    local ok = services.ResourcesService.TrySpendMoney(player, itemId)
    if ok then
        services.InventoryService.AddItem(player, itemId)
    end
end)
```

### R4: Event subscriptions only in subscription modules
All `.Connect()`, `.OnServerEvent`, `.OnClientEvent`, and UI bindings live in
`subscriptions/`. Never inside services or data modules.
**Sole exemption:** library-internal lifecycle signals of a vendored library
(e.g. ProfileStore `OnSessionEnd` / `OnError`) are connected inside the
service that owns that library (ADR-0001). Game/domain events never qualify.

### R5: Clone, don't create
Visual/view objects (effects, UI, models) → template in ReplicatedStorage,
clone at runtime. Never `Instance.new()` for view objects.

### R6: Respect network latency
Smooth motion runs on the **client**. Server is for validation, not visual
updates. Never trust the client: every remote handler validates its inputs.

### R7: One file = one responsibility
Services do one thing. If a file grows past ~300 lines, split it.

### R8: Console Transparency — a silent failure is a bug
All console output goes through `src/shared/Log.lua`
(`Log.Info` = lifecycle event, hidden when `Log.verbose = false`;
`Log.Sum` = always-shown summary; `Log.Warn` = needs attention;
`Log.Once` = repeated-check warn, fires once per key).

Non-negotiable expectations:
- **Every early-return on a missing dependency logs why** (missing folder,
  module without `Init`/`Start`, unresolved GUI, unloaded profile, remote
  push dropped). Never `return` silently from a failure path.
- **Bootstrap reports everything**: which modules loaded per folder, each
  Init/Start ok/failed, and a final summary with counts. A subscription
  without `Start()` warns — it will never run.
- **Dangerous silent states warn loudly** — the canonical example is "no
  DataStore access" (game runs, nothing persists); PersistenceService
  reports the resolved DataStore state on boot.
- **Missing authored UI warns once** with a pointer to the feature doc's GUI
  contract, then the feature degrades gracefully.
- **Late-arriving dependencies never false-positive**: things that
  legitimately show up late (StarterGui clone after spawn, slow replication)
  use `Log.GraceOnce` — a NON-BLOCKING deferred re-check that warns only if
  the dependency still isn't there after the grace period. Never solve this
  with blocking waits (`WaitForChild` with timeouts) in feature flow — slow
  connections would stall the feature instead of logging.
- When reading the console after a run you must be able to answer: what
  loaded, what subscribed, what was skipped, and why.

---

## Strict Rules — Documentation

The `docs/` folder is **part of the codebase**. Maintaining it is not optional.

### D1: Before any task — READ (in this order, and NOTHING more)
1. `docs/MAP.md` — routing index. Find your feature's row; do NOT read other
   features' docs.
2. `docs/features/<feature>.md` — the single self-contained doc for that
   feature (state, remotes + payloads, GUI contract, gotchas).
3. `docs/flow/INDEX.md` — open at most the 1-2 flow docs whose tags match
   the feature you're touching. Never read `flow/` wholesale.
4. `docs/recipes/<recipe>.md` — if MAP or the feature doc names one.
5. `docs/registries/` — ONLY when naming something new (uniqueness check).

**If the feature you're about to touch isn't in `docs/MAP.md` — STOP.** Ask
the user whether it exists elsewhere or is new.

### D2: After any task — WRITE
1. Create `docs/flow/YYYY-MM-DD_<short-task-name>.md` from `docs/flow/_TEMPLATE.md`
2. Append ONE line (date, doc, tags, summary) to `docs/flow/INDEX.md`
3. Update or create `docs/features/<feature>.md` if behavior changed —
   everything an agent needs about the feature goes HERE, nowhere else
4. `docs/MAP.md`: add/adjust the ONE line for the feature or infra piece
   (never add detail to MAP)
5. Register new names (section keys, remotes, kinds, locale keys) in
   `docs/registries/` — name + owner + doc link only
6. Non-obvious architectural decision → `docs/decisions/NNNN-<title>.md`
7. Same pattern used 2+ times → propose a recipe in `docs/recipes/`

### D3: Doc consistency rules — docs are FOR AGENTS
Docs are read by agents under a token budget. Optimize for routing + single
lookup, not for narrative reading:
- **Single source of fact.** Every fact lives in exactly ONE doc; everything
  else links to it. Duplication = future drift = agent reads two conflicting
  versions.
- **MAP is an index**: one line per entry, entry points only, no descriptions.
- **Feature doc is the aggregation point**: self-contained for its feature so
  one read suffices; ≤ 1 page (split into sub-features if longer).
- **Registries are uniqueness indexes**: name → owner + doc link. No shapes,
  no semantics.
- **Don't repeat code.** File headers document responsibility and data
  shapes; docs carry intent, contracts and gotchas. Code is source of truth
  for **behavior**, docs for **intent** — if they conflict, fix the doc.
- Terse tables/lists over prose; stable headings; flow docs = what/why +
  links, no code dumps.

### D4: Naming
- Flow files: `YYYY-MM-DD_kebab-case-name.md`
- Feature files: `kebab-case-name.md`
- ADR files: `NNNN-kebab-case-name.md` (NNNN = next sequential number)
- Recipe files: `add-<thing>.md` or `how-to-<thing>.md`

---

## Code Style

### Module Template

```lua
local ModuleName = {}

local localReference  -- private state (only for caching data module refs)

function ModuleName.Init(data)
    localReference = data.SomeData
end

--API
function ModuleName.DoSomething(player: Player, value: number)
    -- implementation
end

return ModuleName
```

### Subscription Module Template

```lua
local SubsName = {}

function SubsName.Start(data, services)
    -- All .Connect / OnServerEvent / OnClientEvent here
end

return SubsName
```

### Naming Conventions

| Element              | Convention    | Example                          |
|----------------------|---------------|----------------------------------|
| Modules / Classes    | PascalCase    | `PersistenceService`, `PlayerProfileData` |
| Functions            | PascalCase    | `LoadProfile`, `UpdateMoney`     |
| Local variables      | snake_case    | `local player_speed`, `local ok` |
| Data keys (strings)  | kebab-case    | `"music-enabled"`, `"load-failed"` |
| Function parameters  | PascalCase    | `Position: Vector3`              |
| Private locals       | camelCase     | `local profileData`              |

### Formatting

- **Indentation:** tabs (4-space display)
- **Type annotations:** Luau types on parameters (`player: Player`)
- **String interpolation:** backticks (`` `{variable}` ``)
- **Public API:** `--API` comment above public functions
- **Errors:** `pcall()` + `warn()` for non-critical
- **No trailing semicolons**
- Every module opens with a `--[[ ModuleName ... ]]` block describing its
  responsibility; data modules document their full data shape there.

---

## Self-Improvement Loop — PERMANENT RULES

The template lives at `D:\Projects\Roblox\RobloxTemplate`. Games are copies
of it. Anything generalizable discovered while building a game must flow BACK
to the template so every next game starts better. The loop replaces manual
retrospectives — capture happens as part of every task.

### U1: Capture — every task ends with an upstream check
Mandatory Post-Task Checklist item. If during the task you:
- wrote a similar pattern for the SECOND time (within the project or versus
  template code),
- built anything game-agnostic (feature, utility, bugfix, contract or logging
  improvement),
- fixed a bug in copied template code (the template still has it!),
- learned a gotcha worth a rule or recipe,

append ONE row to `docs/upstream/QUEUE.md`. Capture is cheap and mandatory;
judging viability happens later, at harvest — never skip capture because
"it's probably not worth it".

**Codify locally FIRST, queue second.** When the user corrects you or a
lesson is learned, the fix lands in THIS project immediately (rule in this
file's game section, feature-doc gotcha, or recipe — per D2); the queue row
is only the copy for the template. A lesson that lives only in the queue
helps future games but not tomorrow's session here.

### U1b: Notice — the queue has a DEPTH, and somebody must look at it
Capture is automatic; harvest is not. Without a trigger the queue grows
forever and the template stops improving — the failure this rule exists to
prevent (this project captured 200 rows and harvested 0 in three weeks).

Every task, as a Post-Task item, COUNT the pending rows — one cheap command,
no reading:

```bash
grep -c '^| EAC-[0-9]' docs/upstream/QUEUE.md
```

OFFER a bounded harvest ("top 10, P1 first?") when ANY threshold trips:

| Trigger | Threshold |
|---|---|
| depth | ≥ 25 pending rows |
| age | oldest pending row > 14 days |
| severity | ANY `P1` row pending |
| staleness | newest `TEMPLATE_CHANGELOG.md` entry > 30 days old |

You OFFER; you never act on it yourself — U2 still holds. One line is
enough: "Queue is at N (M×P1, oldest D days). Harvest the top 10 now?".
If the user says no, that is a complete answer — do not re-ask next task
unless a NEW threshold trips.

### U2: A game session NEVER silently edits the template
From a game project, `D:\Projects\Roblox\RobloxTemplate` is written only via
the harvest protocol (U3) and only with the user aware it's happening. The
queue is the interface between games and the template. No exceptions.

### U3: Harvest — anti-degradation gates
Applying queue items to the template follows the template's `harvest` skill
(`RobloxTemplate/.claude/skills/harvest/`). Harvest runs in BATCHES OF ≤ 10
candidates — never "the whole queue", which is what made harvest too
expensive to ever start. Triage is a GREP over ids/priorities/claims, never a
read of the whole file; only the picked rows get read in full. An unharvested
`P1` is a bug shipped to every future game — those go first.

Every candidate passes ALL gates:
1. **Proven** — ran in a real project (or, for research items, evidence from
   primary sources), not speculative
2. **General** — game-specific ids/tuning extracted into config; no theme
   leakage
3. **Reviewed** — `adversarial-reviewer` on the ported change
4. **Verified** — `studio-verifier` when runtime behavior changed and Studio
   is connected
5. **Documented** — D2 (docs) + one line in `TEMPLATE_CHANGELOG.md`

Style rewrites of working code are NOT improvements — reject them. When in
doubt, REJECT with a reason: a rejected candidate costs one line; a
regression costs every future game.

A settled row LEAVES the queue: move it to `docs/upstream/ARCHIVE.md` with
its outcome (`harvested <date> <sha>` / `rejected: <reason>`), matched BY ID.
Rejections live there forever so a later harvest cannot re-litigate them —
and the depth in U1b only falls if this actually happens.

### U4: Research — new practices enter through the queue only
The `research-scout` agent gathers evidence (primary sources, dates,
applicability verdict). Findings become queue candidates, never direct
edits. Newer is not better: replacing working, tested code requires a
concrete failure it causes or a measurable win.

## Agents (.claude/agents/)

Three subagents, each earning its context isolation — delegate by TASK SHAPE,
not by "role". No hierarchies, no personas.

| Agent | When |
|---|---|
| `codebase-scout` | Any task requiring bulk reading (surveying a reference project before a port, mapping/auditing many files) — get a report, not raw files in context |
| `adversarial-reviewer` | After implementing any feature or non-trivial change, BEFORE reporting done. Fix its CRITICAL/WARN findings |
| `studio-verifier` | After runtime-behavior changes, when Studio MCP is connected — live playtest + console vs the R8 contract |
| `research-scout` | Checking whether a template approach is still best practice, or gathering evidence for an upstream candidate (U4) — returns sourced report, never edits |

Repeating procedures (add a feature, add a profile section) are recipes in
`docs/recipes/`, not agents.

## Pre-Task Checklist

Before writing any code:
- [ ] Read `docs/MAP.md`
- [ ] Found related feature in `docs/features/` OR confirmed it's new
- [ ] Checked `docs/recipes/` for applicable pattern
- [ ] Scanned last 1-2 `docs/flow/` files for context
- [ ] Identified which files will change

## Post-Task Checklist

Before reporting task complete:
- [ ] Created `docs/flow/YYYY-MM-DD_<task>.md` + one line in `docs/flow/INDEX.md`
- [ ] Updated `docs/MAP.md` if structure changed
- [ ] Updated or created `docs/features/<feature>.md` if applicable
- [ ] Registered new keys in `docs/registries/`
- [ ] Created ADR if a non-obvious decision was made
- [ ] Verified no duplicate functionality with existing services
- [ ] **Upstream capture (U1)**: anything generalizable in this task → one row
      in `docs/upstream/QUEUE.md` (next free `EAC-NNNN` id, a `P` priority,
      and the claim in **bold** — the bold claim is what triage greps)
- [ ] **Upstream depth (U1b)**: count pending rows; if a threshold tripped,
      OFFER a bounded harvest — never perform one unasked (U2)

---

## Common Mistakes to Avoid

- Storing constants or config in services (→ data modules)
- Subscribing to events outside subscription modules
- Calling one service from another (→ coordinate in subscription)
- Adding profile fields outside `ProfileSchema/` sections (→ P1)
- Forgetting `intKeySets` for number-keyed tables (→ P3)
- Using `DataStoreService` directly anywhere (→ P5)
- `Instance.new()` for visual objects (→ clone templates)
- Skipping `docs/MAP.md` and duplicating an existing feature
- Forgetting to update `docs/` after completing a task
