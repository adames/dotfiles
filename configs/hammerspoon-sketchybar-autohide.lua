-- Hide the SketchyBar workspace strip whenever the cursor enters the
-- top of the screen — i.e., whenever the macOS auto-hide menu bar is
-- about to reveal itself. Removes the visual bleed at the 2px boundary
-- where the menu bar sits above sketchybar but doesn't fully cover it.
--
-- 100ms polling timer rather than an eventtap. hs.mouse.absolutePosition
-- is a direct CGEventGet call (no Accessibility/Input-Monitoring
-- permission required, no event-delivery surprises after reload). Lag
-- ceiling is 100ms, which is below the macOS menu bar's own ~250ms
-- reveal animation — imperceptible.

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

M.timer = hs.timer.doEvery(0.1, function()
  set_shown(hs.mouse.absolutePosition().y >= TRIGGER_Y)
end)

return M
