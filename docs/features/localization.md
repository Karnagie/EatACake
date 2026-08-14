# Localization (16 languages, cloud table)

## What it does
Every player-facing string resolves through `LocaleData` against the universe's
**cloud localization table** (universe `10593425705`), machine-translated into 16
languages. English is the Source; no other language ever lives in the repo.

Workbench + how to change a translation: `localization/README.md`.
Toolchain playbook: the user-level `roblox-localization` skill (not in this repo's
`.claude/skills/` — invoke it by name).

## The two mechanisms (both are in use — know which one a string uses)

| Mechanism | Reached by | Used for |
|---|---|---|
| **Key-based** — `Translator:FormatByKey(key, params)` | `LocaleData.T("key", {…})` | Everything set from client code (266 keys). **The only mechanism that survives `{param}` interpolation.** |
| **Source-matching** — `Translator:Translate` / engine `AutoLocalize` | `LocaleData.Tr(text)`, or any TextLabel/ProximityPrompt the server writes | Catalogue + server text that arrives as data: ShopData labels/descs, LobbyQueue messages, world prompts, pad signs, boss name |

A string with a `{param}` can **never** be source-matched — the final rendered
text (`"BELLY 3/10"`) is not in the table. 29 of the 266 keys interpolate; they
depend entirely on the key path.

## Contracts

- **`LocaleData.strings` shape is parsed by a regex.** Keep `LocaleData.strings = {`
  at column 0 and one `["key"] = "value",` per line. The harvester's anchor is
  line-start — writing `LocaleData.strings = { ... }` inside an indented comment is
  safe, at column 0 it would hijack the parse.
- **Key charset is `[A-Za-z0-9_-]`, NOT kebab-only.** Keys are built by
  concatenation (`"hex-name-" .. statId` → `hex-name-biteRadius`); a kebab-only
  harvest silently drops those 8 upgrade-node names.
- **`T` never throws, never yields, never returns nil** for a registered key. It
  falls back to the English template on every failure (no translator yet, unknown
  key in the cloud, sources with no translatable words such as `"{n}"`).
- **`T(key)` returns `key` itself when the key is not in `strings`** (and warns
  once per key). `LocalPetsService.localize` depends on exactly that.
- **`T` does not mutate the caller's `params` table** — numbers are stringified
  into a copy. Stringifying matters: `FormatByKey` renders a raw number as
  `"250.00"`.
- **Number params keep their value** (`tostring`, not rounding): `12.5` → `"12.5"`.
- Translator load is async (`Init` → `task.spawn`). Until it lands every string is
  English; a failed load **warns** (R8) rather than degrading silently.

## Adding or changing a string

| Kind | Where it goes |
|---|---|
| Set from client code | a key in `LocaleData.strings` |
| Server/config text rendered verbatim (`Tr`) | a `catalogues` entry in `localization/localization.config.json` |
| Server-written world text (prompts, signs) | a row in `localization/static_entries.json` |

Then `python tools/robloxloc/robloxloc.py push`. Machine translation fills blank
cells within minutes; `pull` brings them back into the CSV.

## NOT localizable — do not try
- **Kick messages** (`PersistenceData`) — shown by CoreGui before/outside a translator.
- **leaderstats column names** (`Calories`/`Cakes`/`Finds`) — Instance names rendered by CoreGui.
- **Robux purchase prompt copy** — dashboard-side, and dev-product copy is permanently uneditable.
- **Tutorial comic slides** — lettering is baked into the image assets.

## Gotchas
- **⚠ Two entries in ONE PATCH may not share `(source, context)`** — the request is
  rejected with `DuplicatedKeySourceContext` (errorCode 54), **atomically**: one
  duplicate kills all 25 rows in the chunk while the response claims only "1
  failed". This is a per-REQUEST validation, *not* a table constraint: the table
  holds duplicates happily (`upgrade-eat-speed` and `stat-eat-speed` are both
  `("Eat Speed", "")` and both live there) — they just have to arrive in different
  PATCHes. Two keys sharing English is normal (this project has 20 such sources),
  so `chunk_unique_sources()` packs chunks to keep them apart. Do **not** "fix"
  this by assigning contexts; see the next line for why.
- **⚠ A KEY may exist only once in the table.** So re-identifying a row already up
  there (e.g. giving it a context) is a DELETE then an INSERT, never an upsert —
  the insert alone returns `KeyAlreadyExistInTableWithoutExactMatch`. `push`
  detects stale identities and deletes them in a separate pass. This is why
  context-per-key is the wrong tool for the collision above: it costs a
  delete+insert per row and a synthetic context breaks the source matching that
  keyless rows depend on.
- **⚠ Always confirm a push actually landed — `pull` reports it.** A push is
  chunked at 25; a chunk that fails after its retries used to abort the run and
  take every later chunk with it, which is how this table once ended up with 200
  of 300 rows while the CSV looked complete. `pull` now prints `⚠ N row(s) are NOT
  in the cloud table yet` and keeps them OUT of the baseline, so a re-`push`
  uploads exactly the missing ones. Never trust "push finished" — trust `pull`.
- **Studio caches the localization table at session start.** Probing
  `GetTableEntries()` in a Studio session opened before a push shows the OLD
  (possibly empty) table. Verify against the API (`pull`), not in Studio.
- **⚠ Once a key is in the cloud table, the English in `LocaleData.strings` is
  DEAD CODE for that key — including for English players.** `FormatByKey`
  resolves by key and returns the table's stored Source; the local template is
  only a fallback for keys the table does not have. So editing a string in Lua
  changes nothing in the live game until you `push`. It *will* look fixed in an
  unpublished Studio place (no translator → fallback), which is the trap.
- **The first paint is always English.** The translator is a web round trip that
  lands ~0.5-3 s after boot. `LocaleSubsClient` repaints the app via
  `LocaleData.OnReady` when it does. Any NEW surface that renders text outside
  the `AppRoot` React tree must register its own `OnReady` or it will keep the
  English it painted first.
- Matching is **exact and case-sensitive**, trailing spaces included. Harvest from
  real code, never retype from docs.
- A **keyless** row matches by source *globally* — every label in the game
  rendering that exact text becomes eligible. That is why the harvester drops
  sources with no letters (`"200"`): they translate to nothing and only create
  collisions. Keyed rows are exempt.
- Table edits take **minutes** to reach running clients. Verify with `pull`, not by
  restarting Play.
- ATC / "Automatic Text Capture" scraping stays **OFF**: it would add one table row
  per rendered variant (`"BELLY 3/10"`, `"BELLY 4/10"`, …) and burn the quota.
  `shouldUseLocalizationTable` ("Use Translated Content") is a DIFFERENT flag and
  must stay **ON**.
- A manual translation pushed from the CSV **locks** — auto-translation will never
  overwrite it. Game jargon always machine-translates literally, so hand-fix the
  strings that matter most in your own language.

## Files
`src/client/common/data/LocaleData.lua` (strings + `T`/`Tr` + `OnReady`) ·
`src/client/common/subscriptions/LocaleSubsClient.lua` (repaint on locale-ready) ·
`tools/robloxloc/robloxloc.py` · `localization/` (config, `static_entries.json`,
`translations.csv`, `.baseline.json`, README).
