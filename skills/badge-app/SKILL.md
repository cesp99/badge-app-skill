---
name: badge-app
description: Build, fix and ship Lua apps for the Solana Breakpoint 2026 badge (Solana OS, ESP32-C5) — main.lua + app.json packages for the badge App Store. Use this whenever the user wants to make, change, debug, test, sideload or package a badge app or game, mentions Solana OS, the badge, badgeapp.py, LUA_API, on_key/on_tick, ui.label/ui.list, led.fill/led.keep, the mesh, BLE or !LAMPs on the badge, or asks for something to "run on the badge" — even if they don't say "skill" or "Lua".
---

# Solana OS badge apps

A badge app is a folder: `main.lua` (runs first) + `app.json` (manifest) + optional bundled
files. It runs in a sandboxed Lua 5.5 on the badge: 320 × 218 screen, six keys, 8 RGB LEDs.

Paths below are relative to the user's **workspace** (the current project folder). `<skill>`
means this skill's own directory (the base directory shown when the skill loads).

| What | Where |
|---|---|
| Full API reference (source of truth, ~2100 lines) | `solana-os/docs/LUA_API.md` |
| Which radio to use (mesh / BLE / Wi-Fi / http) | `solana-os/docs/CONNECTIVITY.md` |
| Example apps | `solana-os/docs/examples/*/main.lua` |
| Dev CLI (new / check / push / dev / sh / zip) | `<skill>/scripts/badgeapp.py` |
| Verifier (compile + check + on-badge run) | `<skill>/scripts/verify.py` |
| The user's apps | `apps/<id>/` (or wherever the user keeps them) |
| Store zips | `dist/` |

**Get the docs first.** Look for `solana-os/docs/LUA_API.md` in the workspace, or one level up
(`find . .. -maxdepth 3 -name LUA_API.md -path '*solana-os*'`). If there is no copy, clone the
official firmware repo into the workspace (it is public, and only the docs are needed):

```sh
git clone --depth 1 https://github.com/solana-foundation/solana-os
```

If you can't clone, fetch the single file from
`https://raw.githubusercontent.com/solana-foundation/solana-os/main/docs/LUA_API.md`. Don't
write code for modules outside the cheat sheet below without reading their section.

Run the Python tools with `uv run -q --with pyserial --with pillow python3 ...` so pyserial and
Pillow don't need to be installed. Without `uv`, use `pip install pyserial pillow` and plain
`python3`. Define it once per shell to keep commands short:

```sh
BA="uv run -q --with pyserial --with pillow python3 <skill>/scripts/badgeapp.py"
VERIFY="uv run -q --with pyserial --with pillow python3 <skill>/scripts/verify.py"
```

## Workflow

### 1. Read the parts of the API you need

The cheat sheet below covers the everyday surface. For any module beyond `ui`, `led`, `timer`,
`sys`, `storage` and `fs` — `mesh`, `ble`, `http`, `ws`, `rpc`, `lamps`, `items`, `profile`,
`quest`, `crypto`/`solana`, images/canvas — open that section of `LUA_API.md` before writing
code. It is precise about version gates, limits and callback shapes, and guessing those is
the main way badge apps break. Find sections with `grep -n '^##' solana-os/docs/LUA_API.md`
and read the range with `sed -n`. For anything talking to other devices, skim
`CONNECTIVITY.md` and the closest example first.

### 2. Scaffold

New app: `$BA new <id> --name "Name" --author @handle` creates `apps/<id>/` (relative to
the current directory; `--dir` to change it) with a working counter template. Ask the user
for their handle (their X handle as shown in the store) or leave `@you`. Then rewrite both files.

`app.json` rules (the store and `badgeapp check` enforce these):
- `id`: 3–24 chars `a-z 0-9 -`, unique in the store. `name` ≤ 20 chars. `version` semver.
- `icon`: play star heart bell gift home image list wifi shuffle eye edit charge gps settings audio bulb
- `category`: games | tools | social | quests | demos
- `accent`: 6 hex digits, no `#`.
- `permissions`: only what the code uses, from led wifi mesh ble lamps items profile quest http rpc.
  `hosts` lists domains for `http`/`ws`. A module you use without its permission fails with
  `"denied"`, and the store's reviewer looks at extra permissions.
- Bump `version` for every change you plan to publish.

### 3. Write main.lua

Structure: build the UI in the top-level chunk, then define the global callbacks.

```lua
function on_key(key, rep)  -- "up" "down" "left" "right" "select" "back"; rep = auto-repeat
  return true              -- handled. Return false/nil for "back" to let the app exit.
end
function on_tick(ms)       -- every ~30 ms; ms = time since last tick
end
function on_exit()         -- save state here (storage.set), keep LED scenes (led.keep)
end
-- with "mesh": on_mesh(from, msg), on_meet(from, data)
```

Rules that bite, and why:
- **Move things by `ms`, not by tick count.** The tick was 50 ms before 2.1.0 and is 30 ms now.
  Code that counts ticks runs at a different speed on each OS version.
- **"back" must be able to exit.** If `on_key` returns true for every key, the user can only
  leave with HOME. Return false for "back" at the top level of the app. Inside sub-screens,
  use "back" to go up one level.
- **No key-release events.** For held keys or diagonals, read `sys.keys()` in `on_tick`.
- **Lua 5.5, sandboxed.** A `for` loop variable is read-only (`for i=1,3 do i=i+1 end` won't
  compile, so copy it into a local). `io`, `os`, `debug`, `load`, `dofile` and `string.dump`
  are gone, and `collectgarbage` only supports `"count"`. Use `fs`/`require` for bundled
  files and `storage` for saved state.
- **Numbers are 32-bit.** Integers wrap at ±2^31 and floats have about 7 digits, so unix
  milliseconds and lamport amounts overflow. Keep big values as strings or split them.
- **200 000 VM instructions per callback.** Past that the app dies with "Script took too long".
  Spread heavy work across ticks with a coroutine or a work queue, and don't rebuild big
  tables every tick.
- **UI objects are not free.** At most 128 at a time; a `ui.list` costs about 12 KB of SRAM and
  a label about 250 B. Create widgets once and update them (`l:text()`, `r:pos()`, `:show()`).
  Don't call `ui.label` every tick.
- **Feature-gate newer APIs** so the app degrades instead of crashing on older firmware:
  `if led.keep then`, `if ui.image then`, `if sys.keys then`, `if sys.memory then`, `if ui.qr then`.
  `led.keep` (LED scenes that persist after the app closes) is not in the official firmware
  yet; it comes from the `persistent-leds` branch of github.com/cesp99/solana-os. Always
  gate it and have a plain `led.fill`/`led.set` fallback.
- **Async calls take `cb(ok, result)`.** On failure `result` is a string such as "offline",
  "not linked", "denied" or "busy". Handle `ok == false` by showing a toast or a label rather
  than indexing nil.
- `print(...)` goes to the serial console as `[<id>] ...`, which is your debug channel.

Everyday API (check `LUA_API.md` for details and options):

```lua
ui.W, ui.H                                   -- 320, 218 (0,0 top-left, below the status bar)
ui.bg(color)
local l = ui.label(x, y, text, {size=14, color="text", w=nil, align="left", mono=false})
  -- size 12|14|20|32 (12 is mono); align needs w; ≤ 200 bytes per label
l:text(s) l:pos(x,y) l:color(c) l:show(b) l:remove()
local r = ui.rect(x, y, w, h, {color="panel", radius=0, border=nil})  -- r:pos r:size r:color r:show r:remove
local b = ui.bar(x, y, w, h, 0..100)  b:set(v)
local list = ui.list(x, y, w, h, {"a","b"} or {{title=,sub=,right=}}, {on_select=function(i, item) end})
  -- 36 px rows; takes up/down/select while focused; list:items(t) list:selected() list:select(i)
ui.hint("SELECT go   CANCEL exit")       -- 16 px key hint at the bottom: leave room for it
ui.toast("Saved")
ui.confirm("Reset?", function(yes) end)
ui.input("Your name", 16, function(text) end)   -- nil text if cancelled
ui.clear()
-- images (0.5.9+): ui.image(x,y,"art.png"|rows|ui.load(...), {scale=n}), ui.canvas, ui.anim (see LUA_API.md "Images")
-- colours: theme names "text" "dim" "bg" "panel" "border" "purple" "green" "pink" "lpurple"
--          "blue" "aqua" "lime" "yellow" "orange", or 0xRRGGBB

led.count                      -- 8: 1..6 across the top, 7..8 on the right edge  (permission "led")
led.set(i, r, g, b)  led.hex(i, 0xRRGGBB)  led.fill(r, g, b)  led.off()   -- shown at end of callback
led.keep({mode="all", bright=60, all={fx="wave", c1=0x9945FF, c2=0x14F195, speed=4}})  -- if led.keep then

timer.after(ms, fn)  timer.every(ms, fn)  timer.cancel(id)      -- ≤ 8 timers, ≥ 20 ms
sys.millis()  sys.time()  sys.battery()  sys.keys()  sys.memory()  sys.exit()
badge.id()  badge.owner()  badge.online()
json.encode(v)  json.decode(s)
storage.get(k)  storage.set(k, v)  storage.remove(k)            -- 16 KB per app, JSON-able values
require("lib.mod")  fs.read(p)  fs.lines(p)  fs.json(p)  fs.list(dir)  fs.exists(p)  fs.load(p)
```

Layout: the usable area is 320 × 218 with the hint bar taking the bottom 16 px, so content
lives in y ∈ [0, 200]. Centre text with `{w=ui.W, align="center"}`.

When editing an existing app, read the whole `main.lua` first. These apps are usually one
file with sections, and a change in one section often depends on state defined in another.
Keep the existing style and section layout.

### 4. Verify

Use the bundled checker. It always compiles every `.lua` with the local Lua 5.5 (the store
refuses code that doesn't compile) and runs `badgeapp check` (manifest and package limits):

```sh
$VERIFY apps/<id>
```

If no Lua 5.5 `luac` is on PATH, the compile step is skipped with a warning. Tell the user so,
and suggest installing Lua 5.5 (`lua5.5`/`lua` package, or build it from lua.org).

Then, if a badge is plugged in (`ls /dev/ttyUSB0`), test on the device with `--badge`. It
pushes the changed files, launches the app, streams the console, presses keys, takes a
screenshot and fails on any `[lua:<id>] ...` error line:

```sh
$VERIFY apps/<id> --badge --secs 3 --keys "down down select" --shot /tmp/<id>.png
```

The port defaults to `/dev/ttyUSB0`; set `BADGE_PORT` (or `--port`) for others, e.g.
`/dev/ttyACM0` or `/dev/cu.usbserial-*` on macOS.

Pick `--keys` to walk the path you changed, then look at the screenshot with the Read tool:
check that text isn't cut off, nothing overlaps the hint bar and the screen shows what you
expected. A clean launch only proves the app starts; the keys and the screenshot show it
works.

Things to know about the device:
- **Every new serial connection resets the badge** (CH340 DTR/RTS on Linux) and closes the
  running app. That's why verify.py does everything in one connection. Don't follow a run
  with `badgeapp logs` or `sh` and expect the app to still be running.
- `Permission denied` on `/dev/ttyUSB0` (Linux) means the user isn't in the serial group
  (`uucp` on Arch, `dialout` on Debian/Ubuntu/Fedora). Tell the user to run
  `! sudo chmod a+rw /dev/ttyUSB0` (until the next re-plug) or
  `! sudo usermod -aG dialout $USER` (or `uucp`; permanent, needs a re-login). Don't run sudo yourself.
- No badge plugged in: report the static result and say the device test was skipped. Don't
  claim the app works on hardware.
- For an interactive session where the user wants to watch, suggest
  `$BA dev apps/<id> --watch`, which re-pushes on save. It streams forever,
  so don't run it yourself without `timeout`.
- `lua mem` (printed at the end of verify.py) shows the heap peak and the instruction count
  of the last run. Check it if the app is heavy.

### 5. Package and publish

```sh
$BA zip apps/<id>     # -> dist/<id>-<version>.zip
```

Publishing only works in a browser: https://solana.com/breakpoint/badge/apps/submit (signed
in, with X linked). Pick the folder or the zip, try it, then Publish. The store's site answers
scripts with 429 and a browser challenge, so don't try to fetch, curl or automate it. Hand
the user the zip path and the URL. `lamps.award` pays nothing until DevRel grants an
allowance, so mention that if the app awards !LAMPs.

## Reporting back

Tell the user what the app does and how to drive it (keys), which permissions it asks for
and why, and what was verified. Say separately whether it compiled, passed check, ran on the
badge without errors and what the screenshot showed. If you couldn't test on the device,
say so plainly.
