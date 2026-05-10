-- ~/.hammerspoon/init.lua
--
-- Hyper = Ctrl+Opt+Cmd+Shift (sent by Caps Lock via Karabiner).
-- We use Hammerspoon for terminal-targeting hotkeys (Hyper+T, Hyper+N) so the
-- shortcut activates the terminal app even when it isn't frontmost, then
-- forwards Cmd+T / Cmd+N to it. Window-tiling Hyper bindings live in skhd.

-- Allow AppleScript control so the bootstrap can issue `hs.reload()` remotely.
hs.allowAppleScript(true)

-- Quiet startup: suppress the Console window that Hammerspoon shows by
-- default on reload. We surface everything we care about via Hyper+0 and
-- ~/Desktop/Hyper-Keys.html — the Console is just noise during bootstrap.
hs.openConsoleOnDockClick = false
pcall(function()
  local consoleWin = hs.console.hswindow()
  if consoleWin then consoleWin:close() end
end)

local hyper = { "ctrl", "alt", "cmd", "shift" }

-- Order of preference for "the terminal".
local terminals = { "iTerm2", "Alacritty", "kitty", "WezTerm", "Ghostty", "Terminal" }

local function findTerminal()
  for _, name in ipairs(terminals) do
    local app = hs.application.find(name)
    if app then return app end
  end
  return nil
end

local function sendCmd(key)
  return function()
    local app = findTerminal()
    if app then
      app:activate()
      hs.timer.doAfter(0.05, function()
        hs.eventtap.keyStroke({ "cmd" }, key, 0)
      end)
    else
      hs.alert.show("No terminal app found")
    end
  end
end

hs.hotkey.bind(hyper, "t", sendCmd("t"))   -- new tab
hs.hotkey.bind(hyper, "n", sendCmd("n"))   -- new window

-- Optional: SIP-safe Hyper+arrow snapping (works without yabai).
-- These are no-ops when yabai is running and managing tiling, but provide a
-- fallback if SIP cannot be partial-disabled.
local function snap(fraction)
  return function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local f = win:screen():frame()
    win:setFrame({
      x = f.x + f.w * fraction.x,
      y = f.y + f.h * fraction.y,
      w = f.w * fraction.w,
      h = f.h * fraction.h,
    })
  end
end

hs.hotkey.bind(hyper, "left",  snap({ x = 0,    y = 0, w = 0.5, h = 1 }))
hs.hotkey.bind(hyper, "right", snap({ x = 0.5,  y = 0, w = 0.5, h = 1 }))
hs.hotkey.bind(hyper, "up",    snap({ x = 0,    y = 0, w = 1,   h = 1 }))   -- maximize
hs.hotkey.bind(hyper, "down",  snap({ x = 0.25, y = 0.25, w = 0.5, h = 0.5 })) -- center

-- Cheatsheet on Hyper+0 (Caps+0). The "/" bindings were dropped because
-- many apps catch Cmd+? for their Help menu before Hammerspoon's hotkey
-- fires. A static HTML mirror is also written to ~/Desktop/Hyper-Keys.html
-- on every Hammerspoon load.
local meh        = { "ctrl", "alt", "cmd" }
local cheatsheet = require("cheatsheet")
hs.hotkey.bind(hyper, "0", function() cheatsheet.toggle() end)  -- Caps + 0
hs.hotkey.bind(meh,   "0", function() cheatsheet.toggle() end)  -- Caps+Shift + 0

-- Auto-reload config on save
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(files)
  for _, f in ipairs(files) do
    if f:sub(-4) == ".lua" then
      hs.reload()
      return
    end
  end
end):start()

hs.alert.show("Hammerspoon: Hyper bindings active")
