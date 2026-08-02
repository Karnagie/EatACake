# Capture — getting analyzable screenshots + exact region rects

## Roblox Studio (MCP connected)

Two paths; both end in `screen_capture`.

**Play mode** — real data, real HUD. Start play
(`start_stop_play`), navigate UI with `user_mouse_input`
(instance paths like `Players.<name>.PlayerGui.UiRoot.App...` work on kit
buttons), then `screen_capture`.

**Edit-mode React preview harness** — no playtest, ~5s per iteration,
mock props reach states live data cannot (e.g. every card in `buy` state).
Recipe (proven in this project):

1. `execute_luau` (Edit): clone `ReplicatedStorage.Shared.UIKit`, parent the
   clone **inside `ReplicatedStorage.Shared`** (NOT the root — modules
   resolve `script.Parent.Parent.Log`), name it `UIKitPreview`, `require`
   the clone. The CLONE is the point: execute_luau's require cache persists
   across calls, so a direct `require(UIKit)` returns pre-edit code forever.
   **After every file edit, re-clone** (destroy old clone first).
2. `ReactRoblox.createRoot` into a `ScreenGui` (`IgnoreGuiInset = true`)
   parented to `CoreGui`, render the component with mock props. Size panels
   from `workspace.CurrentCamera.ViewportSize` like the demos do.
3. Keep `renderTabs`-style re-render closures in `_G` for later calls.
   You cannot fire React handlers from a script in Edit — to show another
   tab, reorder the `tabs` array so the target is first; drive scroll by
   setting `CanvasPosition` on the ScrollingFrame.
4. Clean up `CoreGui.<Preview>` + `Shared.UIKitPreview` when done.

**Where captures land**: `screen_capture` returns the image inline AND
writes `%LOCALAPPDATA%\Roblox\tmp-capture-storage\wob-<n>` — copy the newest
files and rename to `.png`.

**DPI trap**: capture pixels = viewport * display scale (e.g. viewport
1003x583 → 1505x875 capture at 150%). Region rects from Studio are viewport
px — put the viewport size in the regions JSON `"viewport"` field and
tonal.py rescales automatically.

**Rojo staleness**: before re-capturing after an edit, confirm the edit is
IN Studio — read the module's `.Source` for a marker string (never
`require`, it caches). If stale: accept the Rojo sync prompt, or push via
the localhost bridge (`python -m http.server 8731` in the repo root, then
`execute_luau`: `HttpService:GetAsync("http://127.0.0.1:8731/src/...")` →
write target `.Source`).

## Exact region rects from Studio

`tools/tonal-hierarchy/dump_regions.luau`:

1. Host: `python tools/tonal-hierarchy/tonal.py listen --out dump.json`
2. `execute_luau` the dumper (set `CONFIG.ROOT` to the ScreenGui; localhost
   HttpService works in this project).
3. The dump has exact rects but NO levels — hand-edit: assign
   `level`/`role`, delete layer noise (Rim/Face/Outline duplicates — keep
   the outermost rect per element), drop off-window content. Depth-cut
   children (e.g. price buttons inside cards) can be fetched with a targeted
   `execute_luau` returning `AbsolutePosition/AbsoluteSize` for named
   descendants.

Only annotate what is VISIBLE in the capture: content scrolled out of the
window must be excluded (its AbsolutePosition is outside the scroll window)
or clipped to the visible strip.

Annotation truths learned the hard way:
- **Match production before trusting the gate** — a mock section that
  production drops (empty section => headerless tab) manufactured the only
  persistent CRITICAL of an entire round.
- **UI occluded by a modal scrim is `ignore`** — it is literally
  non-interactive while the panel is open. The saliency model has NO
  luminance prior: dimming preserves local contrast, so a scrim-dimmed HUD
  measures nearly as loud as an undimmed one even though a human reads
  dim = deprioritized.
- **Scrollbars/dividers get `role: chrome`** — infrastructure is judged by
  the background rules, never as an attention rival (at the quiet end of
  the ranking, chrome-vs-element inversions are rank noise).

## Non-Roblox UIs

- Web: Browser pane `computer` screenshot (or `resize_window` first for a
  clean fixed size).
- Desktop apps: computer-use `screenshot`.
- Any PNG/JPG from the user works directly — author regions by measuring
  the image (open it, note rects); `analyze` without `--regions` gives
  hotspots to start from.
