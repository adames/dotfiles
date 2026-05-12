-- Hide the SketchyBar workspace strip whenever the cursor enters the
-- top of the screen — i.e., whenever the macOS auto-hide menu bar is
-- about to reveal itself. Removes the visual bleed at the 2px boundary
-- where the menu bar sits above sketchybar but doesn't fully cover it.
--
-- Single eventtap on mouseMoved + the three drag types. Cheap: each
-- callback is one compare + (only on threshold cross) one subprocess.

local M = {}

-- Trigger zone height. Slightly larger than the macOS menu bar so the
-- strip hides a beat before the menu bar slides in, and stays hidden
-- while the cursor is anywhere over a revealed menu bar.
local TRIGGER_Y = 30

local function find_sketchybar()
  for _, p in ipairs({ "/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar" }) do
    if hs.fs.attributes(p) then return p end
  end
  return nil
end

local SKETCHYBAR = find_sketchybar()
if not SKETCHYBAR then return M end   -- sketchybar not installed; module is a no-op

local shown = true   -- assumes the rc's default of drawing=on

local function set_shown(s)
  if s == shown then return end
  shown = s
  hs.execute(SKETCHYBAR .. " --bar drawing=" .. (s and "on" or "off"))
end

M.tap = hs.eventtap.new({
  hs.eventtap.event.types.mouseMoved,
  hs.eventtap.event.types.leftMouseDragged,
  hs.eventtap.event.types.rightMouseDragged,
  hs.eventtap.event.types.otherMouseDragged,
}, function(event)
  set_shown(event:location().y >= TRIGGER_Y)
  return false   -- pass-through; we observe, not consume
end)

M.tap:start()

return M
