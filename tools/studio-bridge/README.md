# studio-bridge — run scripts in Studio, get structured reports back

The Roblox Studio MCP exposes **zero tools** in this setup, so Studio automation
goes through the command bar. Screenshotting the Output window to read results is
lossy (it truncates, it scrolls, it needs OCR). This is the replacement.

```bash
python tools/studio-bridge/bridge.py 8732
```

- `GET  /<name>` → serves `push/<name>` — push arbitrarily long source INTO Studio
- `POST /<name>` → writes the body to `reports/<name>.txt` — structured results OUT

Studio's `HttpService` reaches `localhost` fine.

## Run a script in Studio

Put the script in `push/`, ending in `return true` (it is required as a
ModuleScript). Then, in the Studio **command bar**:

```lua
local m=Instance.new("ModuleScript") m.Source=game:GetService("HttpService"):GetAsync("http://localhost:8732/inv.lua") m.Parent=workspace require(m) m:Destroy()
```

End the script with:

```lua
game:GetService("HttpService"):PostAsync("http://localhost:8732/inv", table.concat(lines, "\n"), Enum.HttpContentType.TextPlain)
```

## Gotchas, all learned the hard way

| Trap | What to do |
|---|---|
| Studio shows **"Dangerous Command Detected"** for any command-bar HttpService use | Click **Continue**. NEVER "Always Continue" — that permanently disables the user's safety prompt. |
| The command bar's **autocomplete swallows Return** (you get a stray `return ()` on line 2 instead of execution) | Press Escape, then click the **Run** button. |
| A mis-aimed click lands in the **script editor**, and your keystrokes go into real source | `rojo serve` is one-way (disk → Studio) so disk survives; still verify with `git diff`. |
| `require()` **caches per Studio session** | To ask "did this sync?", read `.Source` and search for a marker string. A cached stale table is otherwise indistinguishable from an unsynced module. |
| **Rojo can sit on an unaccepted "Sync changes" prompt** — plugin says Connected, playtest runs fine, but on OLD code | Before trusting any playtest, probe for a marker unique to the change you just made. See `docs/flow/2026-07-26_buried-item-finds.md` pass 19. |
| **`HttpService` fails from the command bar DURING a playtest** — `Http requests can only be executed by game server` | The bar defaults to the CLIENT context in play mode. Stop the playtest, or switch with `Test ▸ Toggle Client View`. This bridge therefore only works from Edit mode (or the server context). |
| **A leftover Output FILTER hides the error telling you why** | Clear the Output filter before diagnosing. A filter set three steps ago made the above error invisible and cost ~8 turns of "the command bar is broken" — it wasn't. |

## Diagnosing "the command bar does nothing"

In order, because each one masks the next:

1. **Clear the Output filter.** If you cannot see errors you are debugging blind.
2. **Is a playtest running?** Then HttpService is unavailable in the bar's default
   (client) context. Stop it.
3. **Re-read the Run button's position from a fresh screenshot** — it moves down as
   the bar grows lines, and Return adds a line instead of executing.
4. **Only then** suspect the bridge. Check its stdout: no request logged means the
   command never ran, which is a Studio-side problem, not a server-side one.

## Why not just print()

`print` goes to a scrolling window you have to photograph. A POSTed report is a
file: greppable, diffable, complete, and it does not lie about what scrolled off.
