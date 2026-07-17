# 2026-07-12: Agent-oriented docs optimization

Tags: docs, map, registries, flow-index

## Task
Docs (especially MAP.md) were trending toward a dump — agents burn tokens
reading everything to find one feature. Restructure docs for agent
consumption WITHOUT losing quality. (Reference disease: Dices MAP.md grew to
170 KB and is read every task.)

## Plan
Three principles: (1) MAP = pure routing index, one line per entry;
(2) single source of fact — the feature doc is the self-contained aggregation
point for its feature, registries shrink to uniqueness indexes (name → owner
+ doc link); (3) task history is discovered via a one-line-per-task
`flow/INDEX.md` with feature tags, never by reading `flow/` wholesale.

## Changes

**Created:**
- `docs/flow/INDEX.md` — tagged one-line index of all flow docs

**Modified:**
- `docs/MAP.md` — rewritten as routing index: Features table (doc + entry
  points), Infrastructure table (file headers are the doc), Lookup section
- `docs/registries/data-keys.md`, `docs/registries/remotes.md` — slimmed to
  uniqueness indexes; payload/field detail removed (lives in feature docs /
  source files)
- `docs/features/persistence.md` — absorbed the ClientReady contract
  (previously only in remotes.md/flow)
- `docs/flow/_TEMPLATE.md` — Tags line (feeds INDEX.md)
- `CLAUDE.md` — D1 rewritten as a strict minimal reading protocol; D2 adds
  INDEX.md append + "one line in MAP, never detail"; D3 rewritten as
  "docs are FOR AGENTS" (single source of fact, MAP-is-index, feature doc =
  aggregation point, registries = names only, don't repeat code)

## Decisions
- Feature doc (not registries, not MAP) is the one place that must fully
  serve an agent working on that feature — reading protocol is MAP row →
  one feature doc → 0-2 tagged flow docs.
- Quality guard: nothing was deleted, only deduplicated — every fact kept
  exactly one home with links from the indexes.
- Infrastructure pieces (Log, Net, bootstraps) intentionally have NO feature
  docs: their file headers are the doc; MAP lists them one line each.

## Open Questions / Followups
- When flow/INDEX.md itself grows large (100+ tasks), archive rows older
  than N months into INDEX-archive.md.
- Port this structure back to Dices someday (its MAP.md is the cautionary tale).

## Related
- Rules: CLAUDE.md D1-D3
- Prior flow: `2026-07-12_console-transparency.md`
