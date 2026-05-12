-- Hammerspoon owns: terminal targeting (Hyper+T/N), SIP-safe arrow snaps,
-- cheatsheet overlay (Hyper+0). Window tiling lives in skhd → yabai.

hs.allowAppleScript(true)   -- bootstrap reloads us via osascript

-- Keep the Hammerspoon Console closed. AppKit re-opens it after init.lua
-- via saved window state; window filters miss the re-open, hence the poller.
hs.openConsoleOnDockClick = false
local function closeConsole()
  pcall(function()
    local w = hs.console.hswindow()
    if w then w:close() end
  end)
end
closeConsole()
hs.timer.new(0.5, closeConsole):start()

local hyper = { "ctrl", "alt", "cmd", "shift" }
local meh   = { "ctrl", "alt", "cmd" }

-- Hyper+T/N: invoke File → New Tab/Window via the menu, not a synthesised
-- keystroke. Reason: when the user is holding Caps (= Hyper), the keystroke
-- arrives as Hyper+Cmd+T which strict apps (Ghostty) don't bind. Menu
-- selection bypasses keyboard state entirely. Falls back to keyStroke for
-- terminals whose menu structure doesn't match.
local PREFERRED_TERMINALS = { "Ghostty", "Terminal" }
local KNOWN_TERMINAL = { Ghostty = true, Terminal = true }

-- Hyper+T → new Ghostty terminal window via the "File → New Window" menu.
-- Native AppKit tabs break yabai's BSP layout (each tab is an extra NSWindow
-- yabai tiles into the same space), so the "give me a new terminal" gesture
-- always creates a top-level window — yabai then tiles it. tmux handles
-- in-window splits (C-Space + v/s). Hyper+N is intentionally unbound.
local MENU_PATHS = {
  t = { { "File", "New Window" }, { "Shell", "New Window" } },
}

local function invokeMenu(app, key)
  for _, path in ipairs(MENU_PATHS[key]) do
    if app:selectMenuItem(path) then return true end
  end
  return false
end

local function sendTerminalCmd(key)
  return function()
    local front = hs.application.frontmostApplication()
    if front and KNOWN_TERMINAL[front:name()] then
      if not invokeMenu(front, key) then
        hs.eventtap.keyStroke({ "cmd" }, key, 0)
      end
      return
    end
    for _, name in ipairs(PREFERRED_TERMINALS) do
      if hs.application.launchOrFocus(name) then
        hs.timer.doAfter(0.3, function()
          local app = hs.application.get(name)
          if app and not invokeMenu(app, key) then
            hs.eventtap.keyStroke({ "cmd" }, key, 0)
          end
        end)
        return
      end
    end
    hs.alert.show("No terminal found: " .. table.concat(PREFERRED_TERMINALS, ", "))
  end
end

hs.hotkey.bind(hyper, "t", sendTerminalCmd("t"))
-- Hyper+N: intentionally unbound. Reserved for future use.

-- Absolute window snaps for floating / yabai-unmanaged windows (Ghostty,
-- System Settings, etc.). Bound on Meh, not Hyper, to keep the layer split
-- coherent:
--   Hyper  = navigate  (Caps + hjkl yabai focus, Caps + 1..8 space focus, …)
--   Meh    = modify    (Caps+Shift + hjkl yabai swap, Caps+Shift + 1..8 send-
--                       to-space, Caps+Shift + arrows manual snap)
-- Bare arrows on the Hyper layer are intentionally unbound — pass through.
local function snap(f)
  return function()
    local w = hs.window.focusedWindow(); if not w then return end
    local s = w:screen():frame()
    w:setFrame({ x = s.x + s.w*f.x, y = s.y + s.h*f.y, w = s.w*f.w, h = s.h*f.h })
  end
end
hs.hotkey.bind(meh, "left",  snap({ x = 0,    y = 0,    w = 0.5, h = 1   }))
hs.hotkey.bind(meh, "right", snap({ x = 0.5,  y = 0,    w = 0.5, h = 1   }))
hs.hotkey.bind(meh, "up",    snap({ x = 0,    y = 0,    w = 1,   h = 1   }))
hs.hotkey.bind(meh, "down",  snap({ x = 0.25, y = 0.25, w = 0.5, h = 0.5 }))

-- Cheatsheet overlay. Dropped Cmd+? bindings — apps eat them for Help menu.
local cheatsheet = require("cheatsheet")
hs.hotkey.bind(hyper, "0", function() cheatsheet.toggle() end)
hs.hotkey.bind(meh,   "0", function() cheatsheet.toggle() end)

-- Workspace OSD + rename. yabai signals call `hs -c "Workspace.show(N,D)"`,
-- so install the CLI shim and load the module on _G.
require("hs.ipc")
if not hs.ipc.cliStatus() then hs.ipc.cliInstall() end
require("workspace")

-- Auto-reload on .lua save.
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(files)
  for _, f in ipairs(files) do
    if f:sub(-4) == ".lua" then hs.reload(); return end
  end
end):start()

hs.alert.show("Hammerspoon: Hyper bindings active")
