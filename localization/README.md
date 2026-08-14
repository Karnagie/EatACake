# Translations workbench

`translations.csv` is the whole game's text: one row per string, English `source`
plus one column per language. Edit cells here, push, done.

Universe `10593425705`. Contract + gotchas: `docs/features/localization.md`.

## Commands

```bash
python tools/robloxloc/robloxloc.py status
```

```bash
python tools/robloxloc/robloxloc.py push
```

```bash
python tools/robloxloc/robloxloc.py pull
```

- **status** — what would be pushed. Local only, touches nothing.
- **push** — uploads new sources + the translation cells you changed.
- **pull** — refreshes the CSV from the cloud, including fresh machine translations.

## Scenarios

**A machine translation is wrong.** Edit that language's cell in `translations.csv`
→ `push`. Your text now **locks**: auto-translation will never overwrite it. This is
the main reason to touch this file — game jargon always translates literally.

**Text changed in the game.** Change it in the code (`LocaleData.strings`, or
`ShopData`, or `static_entries.json`) → `push` → wait a few minutes → `pull` to see
the new machine translations. The old source becomes an orphan row; `push --prune`
deletes orphans from the cloud.

**A new language.** Add its code to `languages` in `localization.config.json` →
`setup` → `push`.

## Rules

- **Never edit the `source` column.** It is regenerated from the code by `pull`;
  an edit there is silently discarded. Change the English in the code instead.
- **Keep `{tokens}` identical** between source and translation — `{n}`, `{fill}`,
  `{cap}`. `push` warns on a mismatch. A dropped token renders a literal `{n}`.
- **Save as UTF-8.** Excel's default "CSV" mangles Cyrillic/CJK — use *CSV UTF-8*,
  or edit in VS Code / Google Sheets.
- **Clearing a cell does nothing.** The tool ignores emptied cells rather than
  pushing a deletion (an empty cell in the portal is a "do not translate" lock).
  To reset one, clear it in the Creator Dashboard.
- **`orphan=yes`** means the row is in the cloud but no longer anywhere in the
  project. Safe to leave; `push --prune` removes them.
- Changes take a **few minutes** to reach running clients.

## Files

| File | What |
|---|---|
| `translations.csv` | the editable table (UTF-8, `key,example,source,<16 langs>,orphan`) |
| `localization.config.json` | universeId, cookie path, language list, harvest rules |
| `static_entries.json` | player-facing strings with no `LocaleData` key (world prompts, pad signs, queue messages) — add an `example` for every one |
| `.baseline.json` | tool-managed sync state. Do not edit; delete only to force a full re-push |

The cookie path in the config points **outside the repo** — a `.ROBLOSECURITY`
cookie is a full account session and must never be committed.
