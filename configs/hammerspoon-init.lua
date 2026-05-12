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

local MENU_PATHS = {
  t = { { "File", "New Tab"    }, { "Shell", "New Tab"    } },
  n = { { "File", "New Window" }, { "Shell", "New Window" } },
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
hs.hotkey.bind(hyper, "n", sendTerminalCmd("n"))

-- SIP-safe window snaps. No-ops when yabai is running (yabai eats Hyper+arrows).
local function snap(f)
  return function()
    local w = hs.window.focusedWindow(); if not w then return end
    local s = w:screen():frame()
    w:setFrame({ x = s.x + s.w*f.x, y = s.y + s.h*f.y, w = s.w*f.w, h = s.h*f.h })
  end
end
hs.hotkey.bind(hyper, "left",  snap({ x = 0,    y = 0,    w = 0.5, h = 1   }))
hs.hotkey.bind(hyper, "right", snap({ x = 0.5,  y = 0,    w = 0.5, h = 1   }))
hs.hotkey.bind(hyper, "up",    snap({ x = 0,    y = 0,    w = 1,   h = 1   }))
hs.hotkey.bind(hyper, "down",  snap({ x = 0.25, y = 0.25, w = 0.5, h = 0.5 }))

-- Cheatsheet overlay. Dropped Cmd+? bindings — apps eat them for Help menu.
local cheatsheet = require("cheatsheet")
hs.hotkey.bind(hyper, "0", function() cheatsheet.toggle() end)
hs.hotkey.bind(meh,   "0", function() cheatsheet.toggle() end)

-- Auto-reload on .lua save.
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(files)
  for _, f in ipairs(files) do
    if f:sub(-4) == ".lua" then hs.reload(); return end
  end
end):start()

hs.alert.show("Hammerspoon: Hyper bindings active")
