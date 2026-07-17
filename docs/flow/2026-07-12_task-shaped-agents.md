# 2026-07-12: Task-shaped subagents

Tags: agents, tooling, review, verification

## Task
Evaluate whether role-based agents (as in multi-agent studio templates) make
sense here; implement what does.

## Plan
Reject job-title hierarchies (directors/leads/specialists): each subagent
starts with a fresh context, so delegation chains lose knowledge and burn
tokens. Keep only roles where isolation itself is the value. Both kept roles
were validated live during template development: the scout produced port
reports instead of flooding context with Dices source; the reviewer caught a
CRITICAL migration data-corruption bug and two feature-killing client bugs.

## Changes

**Created:**
- `.claude/agents/adversarial-reviewer.md` — post-implementation bug hunt;
  enforces R1–R8/P1–P5/D1–D4; verifies vendored API call sites against the
  actual source; severity-ranked output + explicit clean categories
- `.claude/agents/codebase-scout.md` — read-only bulk exploration/porting
  recon; dense reports with "must become config" / "reusable as-is" split
- `.claude/agents/studio-verifier.md` — live playtest via Studio MCP;
  compares console against the R8 healthy-boot contract (encoded in the
  agent definition)

**Modified:**
- `CLAUDE.md` — "Agents" section: delegate by task shape; recipes ≠ agents

## Decisions
- 3 agents, not 36: an agent must earn its fresh-context cost via isolation
  (bulk reads), independence (unbiased review), or tool profile (Studio MCP).
- Procedures stay recipes (`docs/recipes/`) — a slash-command-shaped how-to
  beats a persona for repeatable work.
- The R8 healthy-boot contract lives in studio-verifier's definition — a
  playtest is PASS only if the console proves what loaded/subscribed/skipped.

## Open Questions / Followups
- Possible 4th agent later: docs-auditor (D1–D3 drift check) — hold until
  drift is actually observed; reviewer already checks docs consistency.
- Agent defs are template files — future games inherit them on clone.

## Related
- Rules: CLAUDE.md "Agents", R8
- Prior flow: `2026-07-12_agent-docs-optimization.md`
