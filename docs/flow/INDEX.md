# Flow index

> One line per completed task — append on every task (D2). Agents: find rows
> whose tags match your feature, open at most those 1-2 docs. Never read the
> flow/ directory wholesale.

| Date | Doc | Tags | Summary |
|---|---|---|---|
| 2026-07-11 | `2026-07-11_schema-driven-persistence.md` | persistence, bootstrap, skeleton | ProfileStore vendored, schema sections, repo skeleton, ADR-0001 |
| 2026-07-12 | `2026-07-12_daily-rewards-economy.md` | daily-rewards, economy, reward-grants, net | First feature triads, grant registry (ADR-0002), ClientReady handshake, respawn-proof client |
| 2026-07-12 | `2026-07-12_console-transparency.md` | logging, bootstrap, persistence, ui | Log layer + rule R8, DataStore-state report, GraceOnce for late GUI |
| 2026-07-12 | `2026-07-12_agent-docs-optimization.md` | docs, map, registries, flow-index | MAP → routing index, registries → uniqueness indexes, flow INDEX, D1-D3 rewritten |
| 2026-07-12 | `2026-07-12_task-shaped-agents.md` | agents, tooling, review, verification | 3 task-shaped subagents: scout, adversarial reviewer, studio-verifier (R8 boot contract) |
| 2026-07-12 | `2026-07-12_self-improvement-loop.md` | self-improvement, upstream, agents, template | U1-U4 rules, upstream QUEUE, harvest gates, changelog, research-scout |
| 2026-07-16 | `2026-07-16_feature-library-batch.md` | time-rewards, group-reward, shop, promo-codes, settings, app-root, economy, ui-kit | Feature library: time/group/shop(+passes)/codes/settings-persistence + composed AppRoot (HUD, badges); 28-finding review pass incl. 2 money bugs |
| 2026-07-15 | `2026-07-15_ui-kit-port.md` | ui-kit, ui, skill, packages, bootstrap | Candy-style ReactRoblox UI kit (Theme + 16 components + demos), UiRoot, npm react deps, roblox-ui-kit skill, kit-first UI workflow |
| 2026-07-15 | `2026-07-15_ui-skill-design-step.md` | ui-kit, skill, design | Skill rebalanced after shop-clone failure: mandatory design step, window-archetypes reference (genre structures + worked Shop), list-in-ScrollPane pattern, inventing components declared the norm |
| 2026-07-15 | `2026-07-15_settings-window-react-check.md` | settings, ui-kit, react, packages, bootstrap, r8 | React vendored as ReactLua-Packages.rbxmx (replaces npm/optional-path that infinite-yielded); first real kit feature: startup Settings window (Music / Sound Effects) as React smoke test |
| 2026-07-15 | `2026-07-15_ui-skill-method.md` | ui-kit, skill, design, method | method.md: the author's actual process as mandatory phases — written brief, check-sum zone arithmetic, ratio-transfer element derivation, render-skeleton-first, visual iteration loop (2-4 passes normal), ship gate with iteration report; SKILL.md rewritten (NUL cleanup + phase routing) |
| 2026-07-15 | `2026-07-15_outlined-text-uistroke.md` | ui-kit, text, performance | OutlinedText: 8 clone labels → 1 shadow copy + scaled UIStrokes (StrokeSizingMode ScaledSize, 0.08 main / 0.06 copy, color 27,42,53 as Colors.TextOutline); legacy outline props ignored; callers cleaned; Studio verify pending |
| 2026-07-16 | `2026-07-16_eat-the-cake-v1.md` | cake-sim, cake-cycle, treasures, body-gym, upgrades, pets, rebirth, quests, juice, economy, app-root, map | Eat the Cake v1: heightfield cake + full GDD loop (eat→gym→upgrades→boss→pet→new cake), 12 kit components, Studio-verified end-to-end; ADR-0003/0004; template AppRoot nil-clear bug found+fixed |
| 2026-07-17 | `2026-07-17_cake-grounding-fixes.md` | cake-sim, map | Floating cake (MeshPart renders raw mesh coords from part origin — no bbox recentering), corner see-through slits (analytic ring → 3×3-neighborhood faces), candles moved out of the loaf; "Precise freezes edits" conclusion REVERSED (Automatic's stale LODs were the bug) |
