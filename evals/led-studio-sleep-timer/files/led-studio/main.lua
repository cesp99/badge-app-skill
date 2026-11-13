-- LED Studio: customise the badge's 8 RGB LEDs.
-- Target "All LEDs" runs one effect across the strip; "LED 1".."LED 8" give every LED
-- its own effect, colours and speed. Settings persist; 4 save slots + built-in presets.
-- On Solana OS with led.keep (the "glow"), the scene keeps running after the app closes;
-- elsewhere the LEDs only run while the app is open.

local N = led.count or 8
local floor, sin, cos, pi, random = math.floor, math.sin, math.cos, math.pi, math.random

---------------------------------------------------------------- colours

local PALETTE = {
  {"Off", 0x000000}, {"White", 0xFFFFFF}, {"Warm white", 0xFFB46B}, {"Red", 0xFF0000},
  {"Orange", 0xFF5A00}, {"Amber", 0xFFA000}, {"Yellow", 0xFFE000}, {"Lime", 0x8CFF00},
  {"Green", 0x00FF20}, {"Solana green", 0x14F195}, {"Aqua", 0x00FFC8}, {"Cyan", 0x00C8FF},
  {"Blue", 0x0030FF}, {"Indigo", 0x4B00FF}, {"Solana purple", 0x9945FF},
  {"Magenta", 0xFF00C8}, {"Pink", 0xFF3C78},
}

local function rgb(c) return (c >> 16) & 255, (c >> 8) & 255, c & 255 end
local function pack(r, g, b) return (r << 16) | (g << 8) | b end

local function mix(a, b, t)
  local ar, ag, ab = rgb(a)
  local br, bg, bb = rgb(b)
  return ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t
end

local function scale(c, k)
  local r, g, b = rgb(c)
  return r * k, g * k, b * k
end

local function hsv(h, s, v)              -- h, s, v in 0..1 -> r, g, b in 0..255
  h = (h % 1) * 6
  local i = floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  local r, g, b
  if i == 0 then r, g, b = v, t, p
  elseif i == 1 then r, g, b = q, v, p
  elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v
  elseif i == 4 then r, g, b = t, p, v
  else r, g, b = v, p, q end
  return r * 255, g * 255, b * 255
end

local function to_hsv(c)                 -- -> hue 0..359, sat 0..100, val 0..100
  local r, g, b = rgb(c)
  r, g, b = r / 255, g / 255, b / 255
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d, h = mx - mn, 0
  if d > 0 then
    if mx == r then h = ((g - b) / d) % 6
    elseif mx == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
  end
  return floor(h * 60 + 0.5) % 360, mx > 0 and floor(d / mx * 100 + 0.5) or 0, floor(mx * 100 + 0.5)
end

local function hsv_int(h, s, v)
  local r, g, b = hsv(h / 360, s / 100, v / 100)
  return pack(floor(r + 0.5), floor(g + 0.5), floor(b + 0.5))
end

local function color_name(c)
  for _, p in ipairs(PALETTE) do
    if p[2] == c then return p[1] end
  end
  return string.format("#%06X", c)
end

---------------------------------------------------------------- effects

-- c1/c2: which colours the effect uses. spatial: works across the strip (All LEDs only).
local FX = {
  {id = "solid",    name = "Solid",        c1 = true},
  {id = "breathe",  name = "Breathe",      c1 = true},
  {id = "blink",    name = "Blink",        c1 = true, c2 = true},
  {id = "strobe",   name = "Strobe",       c1 = true, c2 = true},
  {id = "fade",     name = "Fade 2 colors", c1 = true, c2 = true},
  {id = "hue",      name = "Color cycle"},
  {id = "twinkle",  name = "Twinkle",      c1 = true, c2 = true},
  {id = "candle",   name = "Candle",       c1 = true},
  {id = "rainbow",  name = "Rainbow",      spatial = true},
  {id = "gradient", name = "Gradient",     c1 = true, c2 = true, spatial = true},
  {id = "wave",     name = "Wave",         c1 = true, c2 = true, spatial = true},
  {id = "comet",    name = "Comet",        c1 = true, c2 = true, spatial = true},
  {id = "scanner",  name = "Scanner",      c1 = true, c2 = true, spatial = true},
  {id = "theater",  name = "Theater",      c1 = true, c2 = true, spatial = true},
  {id = "police",   name = "Police",       c1 = true, c2 = true, spatial = true},
  {id = "off",      name = "Off"},
}
local FX_BY_ID, FX_ALL, FX_ONE = {}, {}, {}
for _, f in ipairs(FX) do
  FX_BY_ID[f.id] = f
  FX_ALL[#FX_ALL + 1] = f.id
  if not f.spatial then FX_ONE[#FX_ONE + 1] = f.id end
end

local spark, flame = {}, {}
for i = 1, N do spark[i], flame[i] = 0, 0.7 end

-- One LED's colour for effect `fx` with settings `c` ({c1, c2, speed}) at time t.
local function compute(fx, i, t, ms, c)
  local L = 6000 // c.speed               -- one cycle: 6 s at speed 1, 0.6 s at 10
  local p = (t % L) / L
  local pos = (i - 1) / N
  if fx == "solid" then return rgb(c.c1)
  elseif fx == "breathe" then return scale(c.c1, 0.03 + 0.97 * (0.5 - 0.5 * cos(2 * pi * p)))
  elseif fx == "blink" then return rgb(p < 0.5 and c.c1 or c.c2)
  elseif fx == "strobe" then return rgb(p < 0.12 and c.c1 or c.c2)
  elseif fx == "fade" then return mix(c.c1, c.c2, 0.5 - 0.5 * cos(2 * pi * p))
  elseif fx == "hue" then return hsv(p, 1, 1)
  elseif fx == "rainbow" then return hsv(p + pos, 1, 1)
  elseif fx == "gradient" then return mix(c.c1, c.c2, (i - 1) / (N - 1))
  elseif fx == "wave" then return mix(c.c2, c.c1, 0.5 + 0.5 * sin(2 * pi * (p - pos)))
  elseif fx == "comet" then
    local d = (p * N - (i - 1)) % N       -- how far behind the head this LED is
    return mix(c.c2, c.c1, math.max(0, 1 - d / 3))
  elseif fx == "scanner" then
    local x = (p < 0.5 and p * 2 or (1 - p) * 2) * (N - 1)
    return mix(c.c2, c.c1, math.max(0, 1 - math.abs(x - (i - 1)) / 1.5))
  elseif fx == "theater" then
    return rgb(((i - 1) + floor(p * 6)) % 3 == 0 and c.c1 or c.c2)
  elseif fx == "police" then
    local left = i <= N // 2
    local q = left and p or (p + 0.5) % 1
    if q < 0.1 or (q > 0.2 and q < 0.3) then return rgb(left and c.c1 or c.c2) end
    return 0, 0, 0
  elseif fx == "twinkle" then
    local s = spark[i] - ms * c.speed / 1500
    if random() < ms * c.speed / 8000 then s = 1 end
    spark[i] = s > 0 and s or 0
    return mix(c.c2, c.c1, spark[i])
  elseif fx == "candle" then
    local f = flame[i] + (random() - 0.5) * 0.06 * c.speed
    f = f + (0.75 - f) * 0.1
    flame[i] = f < 0.2 and 0.2 or (f > 1 and 1 or f)
    return scale(c.c1, flame[i])
  end
  return 0, 0, 0
end

---------------------------------------------------------------- settings

local function int(v, lo, hi, def)
  v = tonumber(v)
  if not v then return def end
  v = floor(v)
  return v < lo and lo or (v > hi and hi or v)
end

local function clean_fx(c, allowed, def)
  c = type(c) == "table" and c or {}
  local out = {
    fx = FX_BY_ID[c.fx] and c.fx or def.fx,
    c1 = int(c.c1, 0, 0xFFFFFF, def.c1),
    c2 = int(c.c2, 0, 0xFFFFFF, def.c2),
    speed = int(c.speed, 1, 10, def.speed),
  }
  if allowed == FX_ONE and FX_BY_ID[out.fx].spatial then out.fx = "solid" end
  return out
end

local DEF = {fx = "wave", c1 = 0x9945FF, c2 = 0x14F195, speed = 4}

-- Fills in defaults and fixes anything out of range (storage and presets come through here).
local function clean(cfg)
  cfg = type(cfg) == "table" and cfg or {}
  local out = {
    mode = cfg.mode == "each" and "each" or "all",
    keep = cfg.keep ~= false,
    bright = int(cfg.bright, 10, 100, 60),
    all = clean_fx(cfg.all, FX_ALL, DEF),
  }
  if type(cfg.leds) == "table" then
    out.leds = {}
    for i = 1, N do out.leds[i] = clean_fx(cfg.leds[i], FX_ONE, out.all) end
  elseif out.mode == "each" then
    out.mode = "all"                      -- per-LED mode with no per-LED settings
  end
  return out
end

local function copy(cfg) return clean(json.decode(json.encode(cfg))) end

local cfg = clean(storage.get("cfg"))
local target = cfg.mode == "each" and 1 or 0    -- 0 = all LEDs, 1..8 = one LED

local function ensure_leds()
  if cfg.leds then return end
  cfg.leds = {}
  for i = 1, N do cfg.leds[i] = clean_fx(cfg.all, FX_ONE, cfg.all) end
end

local function cur() return target == 0 and cfg.all or cfg.leds[target] end

local function describe(c)
  if c.mode == "each" then return "Custom per-LED" end
  return FX_BY_ID[c.all.fx].name .. ", all LEDs"
end

local function preset(fx, c1, c2, speed)
  return {mode = "all", all = {fx = fx, c1 = c1, c2 = c2, speed = speed}}
end

local BUILTIN = {
  {"Solana",      preset("wave", 0x9945FF, 0x14F195, 4)},
  {"Rainbow",     preset("rainbow", 0, 0, 5)},
  {"Police",      preset("police", 0xFF0000, 0x0030FF, 6)},
  {"Campfire",    preset("candle", 0xFF5A00, 0, 6)},
  {"Ocean",       preset("wave", 0x00C8FF, 0x0018A0, 3)},
  {"Party",       preset("theater", 0xFF00C8, 0x00C8FF, 8)},
  {"Scanner",     preset("scanner", 0xFF0000, 0x000000, 5)},
  {"Starry night", preset("twinkle", 0xFFFFFF, 0x000008, 4)},
  {"Calm breathe", preset("breathe", 0x14F195, 0, 2)},
  {"Off",         preset("off", 0, 0, 5)},
}
local SLOTS = 4

---------------------------------------------------------------- screen: shared

local preview, frames, marker = {}, {}, nil
local shown = {}                          -- last colour drawn per preview LED
local screen = "main"

local function led_box(i)                 -- x, y, w, h of LED i's preview
  if i <= 6 then return 12 + (i - 1) * 46, 8, 34, 16 end
  return 298, 8 + (i - 7) * 26, 14, 22
end

local function build_preview()
  preview, frames, shown = {}, {}, {}
  for i = 1, N do
    local x, y, w, h = led_box(i)
    frames[i] = ui.rect(x - 2, y - 2, w + 4, h + 4, {color = "panel", radius = 5})
    preview[i] = ui.rect(x, y, w, h, {color = 0x000000, radius = 4})
  end
  marker = ui.rect(0, 0, 4, 4, {color = "text", radius = 1})
  marker:show(false)
end

local function place_marker()
  if target == 0 or screen == "presets" then
    marker:show(false)
    for i = 1, N do frames[i]:color("panel") end
    return
  end
  for i = 1, N do frames[i]:color(i == target and "text" or "panel") end
  local x, y, w, h = led_box(target)
  if target <= 6 then marker:pos(x, y + h + 4); marker:size(w, 3)
  else marker:pos(x - 7, y); marker:size(3, h) end
  marker:show(true)
end

---------------------------------------------------------------- screen: main

local ROW_Y, ROW_H = 38, 18
local MAX_ROWS = 9
local rows, hl, names, values, swatches = {}, nil, {}, {}, {}
local sel = 1

local function make_rows()
  rows = {"target", "effect", "c1", "c2", "speed"}
  if target ~= 0 then rows[#rows + 1] = "copy" end
  rows[#rows + 1] = "bright"
  if led.keep then rows[#rows + 1] = "keep" end
  rows[#rows + 1] = "presets"
  if sel > #rows then sel = #rows end
end

local LABEL = {target = "Target", effect = "Effect", c1 = "Color 1", c2 = "Color 2",
  speed = "Speed", copy = "Copy to all", bright = "Brightness", keep = "After exit", presets = "Presets"}

local function value_of(key)
  local c, f = cur(), FX_BY_ID[cur().fx]
  if key == "target" then return target == 0 and "All LEDs" or ("LED " .. target .. " of " .. N)
  elseif key == "effect" then return f.name
  elseif key == "c1" then return f.c1 and color_name(c.c1) or "(not used)", f.c1 and c.c1
  elseif key == "c2" then return f.c2 and color_name(c.c2) or "(not used)", f.c2 and c.c2
  elseif key == "speed" then return string.rep("|", c.speed) .. "  " .. c.speed
  elseif key == "copy" then return "SELECT: LED " .. target .. " -> all"
  elseif key == "bright" then return cfg.bright .. "%"
  elseif key == "keep" then return cfg.keep and "Keep glowing" or "Turn off"
  elseif key == "presets" then return "SELECT to open"
  end
end

local function draw_main()
  make_rows()
  for r = 1, MAX_ROWS do
    local key = rows[r]
    if key then
      local text, swatch = value_of(key)
      names[r]:text(LABEL[key]); names[r]:show(true)
      values[r]:text(text); values[r]:show(true)
      values[r]:color(r == sel and "text" or "dim")
      if swatch then swatches[r]:color(swatch) end
      swatches[r]:show(swatch ~= nil and swatch ~= false)
    else
      names[r]:show(false); values[r]:show(false); swatches[r]:show(false)
    end
  end
  hl:pos(4, ROW_Y + (sel - 1) * ROW_H)
  place_marker()
end

local function build_main()
  screen = "main"
  ui.clear()
  build_preview()
  hl = ui.rect(4, ROW_Y, 284, ROW_H, {color = "panel", radius = 4})
  for r = 1, MAX_ROWS do
    local y = ROW_Y + (r - 1) * ROW_H + 1
    names[r] = ui.label(12, y, "", {size = 14, color = "dim"})
    values[r] = ui.label(108, y, "", {size = 14})
    swatches[r] = ui.rect(262, y + 1, 20, 13, {color = 0, radius = 3, border = "border"})
  end
  ui.hint("UP/DN row  L/R change  SELECT edit  CANCEL exit")
  draw_main()
end

local function cycle(list, value, dir)
  local idx = 1
  for k, v in ipairs(list) do if v == value then idx = k end end
  return list[(idx - 1 + dir) % #list + 1]
end

local function cycle_color(c, dir)
  local idx = 0
  for k, p in ipairs(PALETTE) do if p[2] == c then idx = k end end
  if idx == 0 then idx = dir > 0 and 0 or 1 end
  return PALETTE[(idx - 1 + dir) % #PALETTE + 1][2]
end

local open_color, open_presets      -- other screens, defined below

local function change(key, dir, rep)
  local c = cur()
  if key == "target" then
    target = (target + dir) % (N + 1)
    if target == 0 then cfg.mode = "all" else ensure_leds(); cfg.mode = "each" end
  elseif key == "effect" then c.fx = cycle(target == 0 and FX_ALL or FX_ONE, c.fx, dir)
  elseif key == "c1" or key == "c2" then
    if FX_BY_ID[c.fx][key] then c[key] = cycle_color(c[key], dir) end
  elseif key == "speed" then c.speed = int(c.speed + dir, 1, 10, 5)
  elseif key == "bright" then cfg.bright = int(cfg.bright + dir * (rep and 20 or 10), 10, 100, 60)
  elseif key == "keep" then cfg.keep = not cfg.keep
  else return end
  draw_main()
end

local function activate(key)
  if key == "c1" or key == "c2" then
    if FX_BY_ID[cur().fx][key] then open_color(key) else ui.toast("This effect doesn't use it") end
  elseif key == "copy" then
    local src = cur()
    for i = 1, N do cfg.leds[i] = {fx = src.fx, c1 = src.c1, c2 = src.c2, speed = src.speed} end
    ui.toast("Copied to all " .. N .. " LEDs")
  elseif key == "presets" then open_presets()
  elseif key == "effect" or key == "target" or key == "speed" or key == "bright" or key == "keep" then
    change(key, 1)
  end
end

local function main_key(k, rep)
  if k == "up" then sel = (sel - 2) % #rows + 1; draw_main()
  elseif k == "down" then sel = sel % #rows + 1; draw_main()
  elseif k == "left" then change(rows[sel], -1, rep)
  elseif k == "right" then change(rows[sel], 1, rep)
  elseif k == "select" then activate(rows[sel])
  else return false end                  -- CANCEL: exit the app
  return true
end

---------------------------------------------------------------- screen: colour editor

local ce = {}                            -- slot, original, h, s, v, row, widgets

local function ce_draw()
  local vals = {ce.h, ce.s, ce.v}
  local maxv = {359, 100, 100}
  local c = hsv_int(ce.h, ce.s, ce.v)
  cur()[ce.slot] = c
  for r = 1, 3 do
    local w = floor(150 * vals[r] / maxv[r])
    ce.fill[r]:size(w > 0 and w or 1, 10)
    ce.val[r]:text(tostring(vals[r]))
    ce.name[r]:color(r == ce.row and "text" or "dim")
  end
  ce.fill[1]:color(hsv_int(ce.h, 100, 100))
  ce.fill[2]:color(hsv_int(ce.h, ce.s, 100))
  ce.fill[3]:color(c)
  ce.cursor:pos(4, 72 + (ce.row - 1) * 28)
  ce.swatch:color(c)
  ce.hex:text(color_name(c))
end

open_color = function(slot)
  screen = "color"
  ui.clear()
  build_preview()
  place_marker()
  local c = cur()
  ce.slot, ce.original, ce.row = slot, c[slot], 1
  ce.h, ce.s, ce.v = to_hsv(c[slot])
  ui.label(12, 44, (slot == "c1" and "Color 1" or "Color 2") ..
    (target == 0 and " - all LEDs" or (" - LED " .. target)), {size = 14})
  ce.cursor = ui.rect(4, 72, 4, 20, {color = "green", radius = 2})
  ce.name, ce.fill, ce.val = {}, {}, {}
  local labels = {"Hue", "Saturation", "Brightness"}
  for r = 1, 3 do
    local y = 72 + (r - 1) * 28
    ce.name[r] = ui.label(14, y + 2, labels[r], {size = 14, color = "dim"})
    ui.rect(108, y + 5, 150, 10, {color = "panel", radius = 3})
    ce.fill[r] = ui.rect(108, y + 5, 1, 10, {color = "text", radius = 3})
    ce.val[r] = ui.label(264, y + 2, "", {size = 14, w = 28, align = "right"})
  end
  ce.swatch = ui.rect(14, 160, 120, 34, {color = 0, radius = 6, border = "border"})
  ce.hex = ui.label(146, 168, "", {size = 14})
  ui.hint("UP/DN pick  L/R adjust  SELECT done  CANCEL undo")
  ce_draw()
end

local function color_key(k, rep)
  if k == "up" then ce.row = (ce.row - 2) % 3 + 1
  elseif k == "down" then ce.row = ce.row % 3 + 1
  elseif k == "left" or k == "right" then
    local d = (k == "right" and 1 or -1) * (rep and 10 or 5)
    if ce.row == 1 then ce.h = (ce.h + d) % 360
    elseif ce.row == 2 then ce.s = int(ce.s + d, 0, 100, 100)
    else ce.v = int(ce.v + d, 0, 100, 100) end
  elseif k == "select" then build_main(); return true
  elseif k == "back" then cur()[ce.slot] = ce.original; build_main(); return true
  end
  ce_draw()
  return true
end

---------------------------------------------------------------- screen: presets

local plist, pitems

local function preset_items()
  pitems = {}
  local slots = storage.get("slots") or {}
  for s = 1, SLOTS do
    local saved = slots[s] or slots[tostring(s)]
    pitems[#pitems + 1] = {title = "Slot " .. s, sub = saved and describe(clean(saved)) or "empty",
      right = "RIGHT=save", slot = s, cfg = saved}
  end
  pitems[#pitems + 1] = {title = "Surprise me", sub = "a random effect and colours", random = true}
  for _, b in ipairs(BUILTIN) do
    pitems[#pitems + 1] = {title = b[1], sub = "built-in: " .. describe(clean(b[2])), cfg = b[2]}
  end
  return pitems
end

local function load_cfg(new)
  local bright = cfg.bright
  local leds = cfg.leds
  cfg = clean(copy(new))
  if not new.bright then cfg.bright = bright end
  if not cfg.leds then cfg.leds = leds end           -- keep the per-LED layout around
  target = cfg.mode == "each" and 1 or 0
end

local function surprise()
  local p = function() return PALETTE[random(2, #PALETTE)][2] end
  return preset(FX_ALL[random(1, #FX_ALL - 1)], p(), random(0, 2) == 0 and 0 or p(), random(2, 9))
end

open_presets = function()
  screen = "presets"
  ui.clear()
  build_preview()
  place_marker()
  plist = ui.list(0, 40, 292, 162, preset_items(), {on_select = function(i, item)
    if item.random then load_cfg(surprise()); ui.toast("Surprise!"); return end
    if not item.cfg then ui.toast("Empty slot: RIGHT saves to it"); return end
    load_cfg(item.cfg)
    ui.toast("Loaded " .. item.title)
  end})
  ui.hint("SELECT load  RIGHT save to slot  CANCEL back")
end

local function save_slot(s)
  local slots = storage.get("slots") or {}
  local fixed = {}
  for k = 1, SLOTS do fixed[k] = slots[k] or slots[tostring(k)] or false end
  fixed[s] = copy(cfg)
  storage.set("slots", fixed)
  storage.set("cfg", cfg)
end

local function presets_key(k)
  if k == "back" then build_main(); return true end
  if k == "right" then
    local i = plist:selected()
    local item = pitems[i]
    if item and item.slot then
      local function go()
        save_slot(item.slot)
        ui.toast("Saved to slot " .. item.slot)
        local keep = i
        plist:items(preset_items())
        plist:select(keep)
      end
      if item.cfg then ui.confirm("Replace slot " .. item.slot .. "?", function(yes) if yes then go() end end)
      else go() end
    end
    return true
  end
  return true
end

---------------------------------------------------------------- lifecycle

function on_key(k, rep)
  if screen == "color" then return color_key(k, rep) end
  if screen == "presets" then return presets_key(k) end
  return main_key(k, rep)
end

function on_tick(ms)
  local t = sys.millis()
  local k = cfg.bright / 100
  for i = 1, N do
    local c = cfg.mode == "each" and cfg.leds[i] or cfg.all
    local r, g, b = compute(c.fx, i, t, ms, c)
    r, g, b = floor(r + 0.5), floor(g + 0.5), floor(b + 0.5)
    r, g, b = r > 255 and 255 or r, g > 255 and 255 or g, b > 255 and 255 or b
    led.set(i, floor(r * k), floor(g * k), floor(b * k))
    local col = pack(r, g, b)             -- the screen shows full brightness
    if shown[i] ~= col then
      preview[i]:color(col)
      shown[i] = col
    end
  end
end

-- Hand the scene to the OS so it keeps running after the app closes (Solana OS with led.keep).
local function keep_glowing()
  if not led.keep then return end
  if not cfg.keep then led.keep(nil); return end
  local ok, err = pcall(led.keep, {
    mode = cfg.mode, bright = cfg.bright, all = cfg.all,
    leds = cfg.mode == "each" and cfg.leds or nil,
  })
  if not ok then print("led.keep: " .. tostring(err)) end
end

function on_exit()
  storage.set("cfg", cfg)
  keep_glowing()
end

build_main()
