# headless-sim — run real game modules without Studio

Runs **the actual `src/` modules** under the standalone Luau CLI against a
stubbed Roblox API, so a mechanic can be measured (not just reviewed) when
Studio / the Studio MCP is unavailable — or when you want a number instead of
an opinion. Added 2026-07-26 while reworking buried finds; it immediately caught
four bugs that code review had missed (`flow/2026-07-26_buried-item-finds.md`).

This does **not** replace Studio verification: nothing here renders, so it
proves BEHAVIOUR, never LOOK.

## Get the toolchain

```bash
curl -L -o luau.zip https://github.com/luau-lang/luau/releases/latest/download/luau-windows.zip
```

Unzip anywhere. You get `luau.exe` (run) and `luau-compile.exe` (syntax gate).

⚠ `rojo build` does NOT parse Luau — a stray `end` ships and only explodes at
`require`. Run the compiler over the tree before any playtest:

```bash
for f in $(find src -name '*.lua'); do luau-compile --binary "$f" >/dev/null || echo "FAIL $f"; done
```

## Run a scenario

```bash
python tools/headless-sim/build_sim.py <seed> <mode> && luau tools/headless-sim/sim.luau
```

⚠ Argument 2 is the **mode**, not the file. The scenario FILE is the
`SCENARIO_FILE` env var (default `treasure_scenario.lua`). Passing a filename as
argv[2] silently falls through to the else-branch and runs a different case than
you asked for — it looks like a pass, of the wrong thing.

| | |
|---|---|
| `treasure_scenario.lua` | `easy` (solo), `hard` (4p, work ×5.5), anything else = no-library fallback orbs |
| `pacing_scenario.lua` | mode unused — always runs sections A/B/C |

```bash
SCENARIO_FILE=pacing_scenario.lua python tools/headless-sim/build_sim.py 20260729 easy && luau tools/headless-sim/sim.luau
```

`build_sim.py` inlines every module listed in `MODULES` plus `harness_head.lua`
(the Roblox stub wiring) and the scenario file, and writes `sim.luau`.

## How it works

| File | Role |
|---|---|
| `roblox_stub.lua` | Instance tree, `Vector3`, `CFrame` (**real 3×3 rotation**), `Color3`, `Enum`, `Model:GetBoundingBox/GetPivot/PivotTo/ScaleTo` |
| `harness_head.lua` | fake `game`/`workspace`/`Players`/`RunService`/`task`, a `Log` stub, and the module registry + `require` shim |
| `treasure_scenario.lua` | the buried-find scenario: builds a cake, mows it band by band, asserts on reveal/collect/placement |
| `build_sim.py` | bundles the above + the real `src/` modules into `sim.luau` |

Two non-obvious constraints, both learned the hard way:

- **`require` is shimmed as a LOCAL declared before the inlined module bodies.**
  Game modules call `require(Shared:WaitForChild("X"))`; the shim resolves the
  proxy path against `__REGISTRY`. Shadowing the CLI's global `require` instead
  would be at the mercy of builtin inlining.
- **The stub keeps `Parent` in `_parent`, never as a raw key.** Lua's
  `__newindex` only fires while a key is ABSENT, so raw-setting `Parent` once
  silently bypasses child-list maintenance on every later assignment. That bug
  made a working code path look broken for an hour.

## Adding a scenario

Copy `treasure_scenario.lua`, add whatever modules it needs to `MODULES` (in
dependency order), and point `SCENARIO_FILE` at it. Stub only what the module
actually touches — a wrong stub is worse than no test, so when a stub has to
approximate the engine (as `GetBoundingBox` does: it returns the box in the
PIVOT's frame, NOT world axes), reproduce the real semantics, not the
convenient ones.
