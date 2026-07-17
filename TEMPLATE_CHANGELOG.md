# Template changelog

> One line per harvested change (gate U3.5). Newest first. Existing game
> projects pull improvements DOWN by diffing their copy against entries newer
> than their copy date.

| Date | Change | Source |
|---|---|---|
| 2026-07-16 | Feature library: time rewards, group reward (shop Free row), shop (dev products + gamepasses, all-or-nothing receipt grants, sole ProcessReceipt owner), promo codes (net-new), settings persistence (SetSetting + SettingsUpdate, section-as-whitelist); composed **AppRoot** single React root (gold HUD pill, menu column with claimable badges, 5 kit panels via openPanel); 7 new kit components (Badge, DayCard, RewardsPanel, ShopRow, ShopPanel, TextInput, CodesPanel) + 9 Theme sections; daily rewards client migrated to kit (Studio-authored path retired); adversarial review pass fixed 2 money bugs, dead ticker (jsdotlua nil-in-deps), list-inflation layout bug. NOT yet visually verified in Studio | this template (Dices logic ports + net-new) |
| 2026-07-15 | React packages VENDORED as `ReactLua-Packages.rbxmx` (one model: `Packages` folder with React + ReactRoblox + node_modules) mapped to `ReplicatedStorage.Packages` — replaces the npm/npmluau + optional-path setup that infinite-yielded when `npm install` was skipped. No build step; copies get React out of the box. `UiRoot.Render` now returns success so callers log honestly. First real kit-rendered feature: **settings** window (SettingsData + LocalSettingsService + SettingsSubsClient) doubling as the React smoke test | this template |
| 2026-07-15 | UI kit: candy-style ReactRoblox kit (`Shared.UIKit`: Theme + 16 components + demos), UiRoot client module, jsdotlua react npm deps (optional rojo path), `roblox-ui-kit` agent skill (style rules / components / patterns), kit-first UI workflow in CLAUDE.md | uitest place (visually verified live) |
| 2026-07-12 | Baseline: schema-driven persistence on vendored ProfileStore (ADR-0001), economy, reward-grant registry (ADR-0002), daily rewards, Log/R8 console transparency, agent-optimized docs (D1-D3), 4 subagents, self-improvement loop (U1-U4) | initial |
