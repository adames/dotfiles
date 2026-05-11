-- ~/.hammerspoon/init.lua
--
-- Hyper = Ctrl+Opt+Cmd+Shift (sent by Caps Lock via Karabiner).
-- We use Hammerspoon for terminal-targeting hotkeys (Hyper+T, Hyper+N) so the
-- shortcut activates the terminal app even when it isn't frontmost, then
-- forwards Cmd+T / Cmd+N to it. Window-tiling Hyper bindings live in skhd.

-- Allow AppleScript control so the bootstrap can issue `hs.reload()` remotely.
hs.allowAppleScript(true)

-- Quiet startup: keep the Console window closed. Hammerspoon's AppKit
-- layer restores it from saved state after init.lua finishes, and window
-- filters miss re-opens of an already-existing window — so we use a tiny
-- polling timer. Cost: one PID-equivalent check every 500ms; negligible.
-- To debug, comment out _consolePoller:start() and use the Hammerspoon
-- menu-bar icon → "Open Console".
hs.openConsoleOnDockClick = false
local function closeConsole()
  pcall(function()
    local w = hs.console.hswindow()
    if w then w:close() end
  end)
end
closeConsole()
local _consolePoller = hs.timer.new(0.5, closeConsole)
_consolePoller:start()

local hyper = { "ctrl", "alt", "cmd", "shift" }

-- Terminal targeting for Hyper+T / Hyper+N.
--
-- Order of preference for installed-but-not-running case. The first one that
-- successfully launches wins. If the user is *already in* a terminal,
-- we short-circuit and just send Cmd+T (or Cmd+N) without re-targeting.
local PREFERRED_TERMINALS = { "Ghostty", "iTerm", "Terminal", "Alacritty", "kitty", "WezTerm" }
local KNOWN_TERMINAL = {
  Ghostty = true, iTerm = true, iTerm2 = true, Terminal = true,
  Alacritty = true, kitty = true, WezTerm = true,
}

local function sendTerminalCmd(key)
  return function()
    -- Fast path: already in a terminal, just send the keystroke.
    local front = hs.application.frontmostApplication()
    if front and KNOWN_TERMINAL[front:name()] then
      hs.eventtap.keyStroke({ "cmd" }, key, 0)
      return
    end
    -- Else launch/focus the first available preferred terminal.
    -- launchOrFocus returns true if the app exists (running or not), false otherwise.
    for _, name in ipairs(PREFERRED_TERMINALS) do
      if hs.application.launchOrFocus(name) then
        hs.timer.doAfter(0.3, function()
          hs.eventtap.keyStroke({ "cmd" }, key, 0)
        end)
        return
      end
    end
    hs.alert.show("No terminal app found (tried: " .. table.concat(PREFERRED_TERMINALS, ", ") .. ")")
  end
end

hs.hotkey.bind(hyper, "t", sendTerminalCmd("t"))   -- new tab
hs.hotkey.bind(hyper, "n", sendTerminalCmd("n"))   -- new window

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
-- fires.
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
