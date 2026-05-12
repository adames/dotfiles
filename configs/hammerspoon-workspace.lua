-- Workspace OSD + interactive rename. Loaded from init.lua via require.
--
-- Public surface (also set on _G so the `hs -c "Workspace.show(2,1)"`
-- call from the yabai signal handler reaches it):
--   Workspace.show(index, display_id)   render OSD on the screen
--   Workspace.rename()                  prompt to rename current space

local json = require("hs.json")

local M = {}

-- ── Config ───────────────────────────────────────────────────────────────

local CONFIG_PATH = os.getenv("HOME") .. "/.config/workspace/spaces.json"
local HANDLER     = os.getenv("HOME") .. "/.config/workspace/on-space-changed.sh"

-- Catppuccin Mocha base palette.
local BG_HEX    = "#1e1e2e"    -- base
local FG_LIGHT  = "#cdd6f4"    -- text (used on dark accents)
local FG_DARK   = "#1e1e2e"    -- text (used on light accents)
local MUTED_HEX = "#9399b2"    -- subtext0

local FADE_IN_S  = 0.18
local HOLD_S     = 0.22
local FADE_OUT_S = 0.20

-- Pick the first installed font from a preference list. Nerd-font glyphs
-- in spaces.json (icons like ) only render correctly with a patched
-- font; falls back to system monospace, then system UI font, so the OSD
-- never renders boxes even if no nerd font is installed.
local function chooseFont(...)
  local set = {}
  for _, n in ipairs(hs.styledtext.fontNames()) do set[n] = true end
  for _, candidate in ipairs({...}) do
    if set[candidate] then return candidate end
  end
  return ".AppleSystemUIFont"
end
-- PostScript names registered by the brew cask (verified post-install).
-- The "NF" and "NFM" variants differ in glyph width — use NF (proportional
-- icon widths) for the OSD label; it looks less cramped than NFM (mono).
local OSD_FONT = chooseFont(
  "JetBrainsMonoNF-Bold",
  "JetBrainsMonoNLNF-Bold",
  "JetBrainsMonoNFM-Bold",
  "MesloLGS NF",
  "FiraCode Nerd Font",
  "Hack Nerd Font",
  "SF Mono",
  "Menlo"
)

-- ── Helpers ──────────────────────────────────────────────────────────────

local function hex_to_rgb(hex)
  -- "#rrggbb" → table for hs.canvas
  local r = tonumber(hex:sub(2, 3), 16) / 255
  local g = tonumber(hex:sub(4, 5), 16) / 255
  local b = tonumber(hex:sub(6, 7), 16) / 255
  return { red = r, green = g, blue = b, alpha = 1.0 }
end

local function hex_to_rgba(hex, alpha)
  local c = hex_to_rgb(hex); c.alpha = alpha; return c
end

local function luminance(hex)
  -- Relative luminance per WCAG; used to pick readable foreground.
  local r = tonumber(hex:sub(2, 3), 16) / 255
  local g = tonumber(hex:sub(4, 5), 16) / 255
  local b = tonumber(hex:sub(6, 7), 16) / 255
  local function f(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
end

local function readMeta()
  local f = io.open(CONFIG_PATH, "r"); if not f then return {} end
  local raw = f:read("*a"); f:close()
  local ok, decoded = pcall(json.decode, raw)
  return ok and decoded or {}
end

local function lookup(index)
  local meta = readMeta()
  local entry = meta.spaces and meta.spaces[tostring(index)] or {}
  return {
    index = index,
    name  = entry.name  or ("ws" .. tostring(index)),
    color = entry.color or MUTED_HEX,
    icon  = entry.icon  or "",
  }
end

local function screenForDisplay(display_id)
  -- yabai display ids are 1..N. hs.screen.allScreens() order generally
  -- matches but isn't guaranteed across reboots — fall back to main.
  local screens = hs.screen.allScreens()
  if type(display_id) == "number" and screens[display_id] then
    return screens[display_id]
  end
  return hs.screen.mainScreen()
end

-- ── OSD ──────────────────────────────────────────────────────────────────

local _active = nil  -- { canvas = hs.canvas, timer = hs.timer }

local function cancelActive()
  if not _active then return end
  if _active.timer then _active.timer:stop(); _active.timer = nil end
  if _active.canvas then _active.canvas:delete(); _active.canvas = nil end
  _active = nil
end

function M.show(index, display_id)
  cancelActive()

  local entry = lookup(index)
  local screen = screenForDisplay(display_id)
  local f = screen:frame()

  -- Sizing: width scales with name length but stays bounded so OSD doesn't
  -- balloon if the user names a workspace something silly.
  local label = string.format("  %d  %s", entry.index, entry.name)
  if entry.icon and entry.icon ~= "" then
    label = string.format("  %d  %s  %s", entry.index, entry.icon, entry.name)
  end
  local W = math.min(420, math.max(180, 90 + #entry.name * 16))
  local H = 64

  local x = f.x + (f.w - W) / 2
  local y = f.y + f.h * 0.32 - H / 2

  local fg = luminance(entry.color) > 0.55 and FG_DARK or FG_LIGHT

  local c = hs.canvas.new({ x = x, y = y, w = W, h = H })
  c:level(hs.canvas.windowLevels.overlay)
  -- '+' (not '|') because Hammerspoon embeds LuaJIT = Lua 5.1, which has
  -- no bitwise operators; the values are disjoint powers of 2 so addition
  -- is equivalent to bitwise OR.
  c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
           + hs.canvas.windowBehaviors.stationary)

  -- background card
  c[1] = {
    type = "rectangle",
    action = "fill",
    fillColor = hex_to_rgba(BG_HEX, 0.92),
    roundedRectRadii = { xRadius = 12, yRadius = 12 },
  }
  -- subtle border
  c[2] = {
    type = "rectangle",
    action = "stroke",
    strokeColor = hex_to_rgba(MUTED_HEX, 0.25),
    strokeWidth = 1,
    roundedRectRadii = { xRadius = 12, yRadius = 12 },
  }
  -- accent bar (workspace color)
  c[3] = {
    type = "rectangle",
    action = "fill",
    fillColor = hex_to_rgb(entry.color),
    frame = { x = 0, y = 0, w = 8, h = H },
    roundedRectRadii = { xRadius = 4, yRadius = 4 },
  }
  -- label
  c[4] = {
    type = "text",
    text = hs.styledtext.new(label, {
      font = { name = OSD_FONT, size = 18 },
      color = hex_to_rgb(fg),
      paragraphStyle = { alignment = "left" },
    }),
    frame = { x = 18, y = (H - 24) / 2 - 2, w = W - 24, h = 28 },
  }

  c:show(FADE_IN_S)

  _active = { canvas = c, timer = nil }
  _active.timer = hs.timer.doAfter(FADE_IN_S + HOLD_S, function()
    if _active and _active.canvas == c then
      c:hide(FADE_OUT_S)
      hs.timer.doAfter(FADE_OUT_S, function()
        if _active and _active.canvas == c then
          c:delete()
          _active = nil
        end
      end)
    end
  end)
end

-- ── Rename ───────────────────────────────────────────────────────────────

function M.rename()
  -- Resolve current space via yabai. Done synchronously — we're already
  -- in Hammerspoon's main thread.
  local cmd = "yabai -m query --spaces --space 2>/dev/null"
  local out = hs.execute(cmd, true)
  if not out or out == "" then
    hs.alert.show("Workspace: yabai unavailable")
    return
  end
  local ok, parsed = pcall(json.decode, out)
  if not ok or not parsed or not parsed.index then
    hs.alert.show("Workspace: bad yabai response")
    return
  end

  local index = parsed.index
  local current = lookup(index)

  local button, text = hs.dialog.textPrompt(
    "Rename workspace " .. index,
    "New name (current: " .. current.name .. ")",
    current.name, "OK", "Cancel"
  )
  if button ~= "OK" then return end
  text = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if text == "" then return end

  -- Mutate the metadata table in-Lua and write the JSON directly. Avoids
  -- shell-quoting the user's name (which can contain quotes, backslashes,
  -- spaces — anything os.execute would mangle).
  local meta = readMeta()
  meta.spaces = meta.spaces or {}
  meta.spaces[tostring(index)] = meta.spaces[tostring(index)] or {}
  meta.spaces[tostring(index)].name = text

  -- Atomic write: tmp + rename. Keeps the file valid even if we crash.
  local tmp = CONFIG_PATH .. ".tmp." .. tostring(hs.host.uuid())
  local f, openErr = io.open(tmp, "w")
  if not f then
    hs.alert.show("Workspace: cannot write " .. CONFIG_PATH .. " (" .. tostring(openErr) .. ")")
    return
  end
  f:write(json.encode(meta, true))
  f:close()
  os.rename(tmp, CONFIG_PATH)

  -- Fire the standard cascade — tmux env, current.env, overlay all
  -- refresh from a single source. Backgrounded so the dialog returns
  -- immediately; cascade is ~50ms anyway.
  hs.execute("'" .. HANDLER:gsub("'", "'\\''") .. "' &", true)
end

-- Expose globally so `hs -c "Workspace.show(N, D)"` reaches us.
_G.Workspace = M

return M
