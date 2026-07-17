# Daily quests

## What it does
GDD §12.2: 3 quests per UTC day (eat 2 cakes / burn 10k calories / uncover
5 finds). Progress = TODAY'S DELTA of lifetime stats in profile section
`progress`, measured against a baseline snapshot anchored on the first read
of the day — zero per-event hooks anywhere in the codebase. Rollover
(dayIndex change) re-anchors and clears claims lazily.

## State / config
Profile section `quests` `{dayIndex, baseline, claimed}`;
`QuestsData.quests` = `{id, statKey, target, reward}` (catalogue, R1).

## Flow
`ClaimQuest` remote (id) → QuestsSubs: `HasHandler` check BEFORE consuming
(ADR-0002 — a mistuned reward never eats a claim) → `QuestService.TryClaim`
→ `RewardGrantSubs.Grant` → `QuestsUpdate {quests}` resync (either way).
Rows: `{id, target, progress, claimed, reward}`; client renders name/reward
via locale keys `quest-<id>` / `quest-reward-*`.

## Files
`ProfileSchema/QuestsSection`, `QuestsData`, `services/QuestService`,
`subscriptions/QuestsSubs`; client `QuestsSubsClient`, kit
`QuestsPanel`/`QuestRow`.
