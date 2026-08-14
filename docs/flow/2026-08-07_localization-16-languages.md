# 2026-08-07: Localization — stub → 16 languages on the cloud table

Tags: localization, ui-kit, shop, lobby-matchmaking, app-root, config, tooling, docs

## Task
"Check if translating is working" → it was not → "use the skill and translate",
with a `.ROBLOSECURITY` path supplied.

## Context
`LocaleData` was an explicit STUB: `T` looked a key up in a hardcoded English
table and `gsub`'d `{params}`; `Tr` was `return text`. No `LocalizationService`
anywhere in the repo, no `localization/`, no workbench.

**The diagnosis was made against the live universe, not the code** — Studio MCP,
Edit mode, universe `10593425705`:

- `FormatByKey("btn-claim")` → THROW `Key btn-claim not found for locale ru`
  (same for every key tried) — the key mechanism had nothing to find.
- `Translate(game, s)` translated **0 of 7** real sources for `ru`/`pt-br`/`es`/`tr`.
- `LS:GetTableEntries()` → **1 entry**, `Key="nil" Source="nil" langs={}` — the
  cloud table was an empty shell.
- The only `LocalizationTable` in the DataModel was `GuiService.FoundationLocalization`
  (Roblox's own core UI, 47 entries).

So BOTH mechanisms were dead, and the repo alone could not have proven the second
one — worth remembering that the cloud half of this feature is invisible to grep.

An 8-agent audit inventoried the string surface: 242 keys already centralized (the
expensive part was done), but four English sources bypassed the key system —
ShopData labels/descs, LobbyQueue messages, world ProximityPrompts, pad signs.

## Plan
Follow the `roblox-localization` skill. Keep the 242-key table byte-identical;
swap only the resolvers; route the four bypass sources through the SOURCE-matching
half (static entries + a catalogue rule) rather than refactoring them into keys.

## Changes

**Created:**
- `tools/robloxloc/robloxloc.py` — harvest/sync CLI (from the skill, two fixes below)
- `localization/localization.config.json` — universe, cookie path (outside the repo), 16 languages, harvest rules
- `localization/static_entries.json` — 28 keyless sources with `example` context
- `localization/translations.csv` + `.baseline.json` — the editable table + sync state
- `localization/README.md` — the human workflow
- `docs/features/localization.md` — the contract

**Modified:**
- `src/client/common/data/LocaleData.lua` — real `T`/`Tr` + `Init`; strings table untouched
- `docs/MAP.md`, `docs/registries/data-keys.md` — feature row + key-charset warning

## Decisions

**No refactor of the four bypass sources.** `AppRoot.localizeMessage` already
falls through to `Tr`, and ProximityPrompt/TextLabel writes are source-matched by
`AutoLocalize` (default true, never disabled here). So 14 LobbyQueue sentences, 6
world prompts, 4 pad signs and the boss name become translatable by *listing* them
in `static_entries.json` — zero code change on the server. Refactoring them into
keys would have been churn with the same outcome.

**Two harvester bugs found and fixed — both silent-data-loss, both generic:**

1. The stock key regex was `[a-z0-9\-]+` (kebab-only). EatACake builds keys by
   concatenation — `"hex-name-" .. statId` → `hex-name-biteRadius` — so **8
   upgrade-node names were silently dropped** from the harvest. Widened to
   `[A-Za-z0-9_\-]`. A dropped row is invisible: no error, just English forever.
2. The table regex `\.strings\s*=\s*\{(.*?)\n\}` was **unanchored**, so it matched
   the `LocaleData.strings = { ... }` example inside the module's own header
   comment; the capture then started in the comment and harvested a bogus
   `["key"] = "value"` row. Caught it by asserting harvested-count against
   declared-count (243 vs 242). Now anchored to column 0 with `re.M`. I wrote that
   comment myself while installing the skill's own template header — the trap is
   in the template.

**`tostring(v)`, not `math.floor(v + 0.5)`,** for number params. The template
rounds; Luau's `tostring` already renders `250` as `"250"` (which is the whole
point — `FormatByKey` renders a raw number as `"250.00"`) while preserving `12.5`.
Rounding would silently corrupt any fractional value.

**`T` copies the params table** instead of stringifying in place. Callers pass
tables they still own and read; the template mutates the caller's table.

**Keyless sources with no letters are dropped from the harvest.** A ShopData
bundle chip is `text = "200"`, and a keyless row matches by exact SOURCE
*globally* — once `"200"` is a source, every label in the game that renders
`"200"` becomes eligible for substitution (Arabic can swap in Arabic-Indic
digits). It has nothing to translate anyway. Keyed rows are exempt: they match by
key, and `"{n}"` templates are legal there.

**Kept the once-per-key `missingWarned`** from the old stub (the skill template
warns on every call): `announce-*`/`pet-*` keys resolve inside React renders, so a
plain `warn` spams. `T(key) == key` on a missing key is also a contract
`LocalPetsService.localize` depends on.

## Adversarial review — what it caught (all fixed)

Two CRITICALs, and the first one was a design hole I would not have found by testing:

1. **`push` recorded REJECTED rows in the baseline**, so a partial failure was
   permanent: the next `status` diffs against a baseline claiming those rows are
   synced, says "nothing to push", and the edit is lost forever with no way to
   notice. Now only server-ACCEPTED identities enter the baseline (a chunk whose
   failures can't be parsed is excluded wholesale — a re-push is idempotent), and
   `push` exits non-zero on any failure.
2. **Nothing repainted the UI when the translator landed.** `translator` is set
   inside `task.spawn`, but React only re-renders through `AppRoot.Set` — so the
   first screen a non-English player sees (the onboarding comic, the idle lobby
   menu) would render English and *stay* English until some unrelated state patch
   happened to repaint it. Added `LocaleData.OnReady` + a new `LocaleSubsClient`
   that bumps one state field. The trigger lives in `subscriptions/` (R4).

Also fixed: `T(nil)` threw `table index is nil` from inside a React render (config
`*Key` fields are unguarded — one missing `descKey` would have taken down the whole
tree); every `FormatByKey` miss was swallowed silently, which is the R8 dangerous-
silent-state — a console reading "translator ready" while 100% of strings fell back
to English — now a first-miss warn naming the fix plus one line per key; a HUNG
`GetTranslatorForPlayerAsync` logged nothing at all (neither pcall branch runs) →
`Log.GraceOnce`; raw `warn()` bypassed `Log` (R8 channel) → namespaced `Log.Once`;
pulled machine translations were never `{token}`-validated (the check only ran on
rows staged for push, and `pull` writes the baseline it would diff against) → now
checked in `pull`; committed absolute cookie path → `$ROBLOSECURITY_FILE` wins,
with a readable exit instead of a traceback; `unesc` mangled `C:\new`; `load_baseline`
crashed on a BOM.

**Reversed one of my own decisions.** I had let the harvester drop keyless statics
whose source collides with a keyed row ("Gym", "Upgrades", "Easy"/"Medium"/"Hard"),
trusting the skill's "keyed row wins". That is an unverified claim about engine
source-matching — and this whole task exists because untested assumptions left
translation dead. A cloud identity is `(key, context, source)`, so the two rows are
legal side by side; they now coexist, the world text is covered either way, and the
statics keep their own `example` (machine translation renders a bare "Easy" as an
adverb without one). Costs 9 rows.

## Verification

- Offline harvest gate: 242 declared / 242 harvested / 0 missed / 0 junk.
- Studio (Edit, real synced source), after the review fixes: LocaleData and the new
  `LocaleSubsClient` both require OK; 242 keys; English fallback gives clean
  integers (`250 cal`, not `250.00`) and preserves floats (`+12.5 Gems`); missing
  key returns the key (LocalPetsService contract); **`T(nil)` and `T("")` no longer
  throw**, they return `""`; `OnReady` queues rather than firing early; caller's
  params table not mutated; `LocaleSubsClient.Start({}, {})` degrades with a warn
  instead of throwing.
- `setup` OK — 16 languages, auto-translation on, **Use Translated Content ON**.
  Quota after: 539,546 / 550,000 monthly + 2.75M bank; this push costs ~70k.
- `status`: 301 rows queued, 0 warnings, 0 orphans.

## Open Questions / Followups

- **`push` is BLOCKED and the feature is not live until it runs.** The permission
  classifier refused it on both Bash and PowerShell. Sources are staged in the CSV;
  one `push` uploads them and machine translation fills the blanks in minutes.
- After the first `pull` with translations: hand-fix the highest-traffic Russian
  strings. Game jargon always machine-translates literally.
- `TreasureConfig` declares 9 `find-*` nameKeys that exist in NO locale table and
  are read by nobody — a dead contract that would render the literal key if wired.
  The registry claims those keys exist. Not touched here.
- Not localizable and documented as such: kick messages, leaderstats column names,
  Robux prompt copy, tutorial comic art.

## Related
- Feature: `docs/features/localization.md`
- Workbench: `localization/README.md`
- Skill: `roblox-localization`
