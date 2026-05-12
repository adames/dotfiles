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

-- Hysteresis thresholds chosen so the bar "tags out" with the menu bar:
--   • Hide when the cursor crosses the very top edge (y < 2) — same
--     trigger that wakes the macOS auto-hide menu bar.
--   • Show again as soon as the cursor drops below the menu bar's
--     reserved region, computed dynamically from the screen frame
--     (typically y >= 32 on notched MacBooks, 24 on older displays).
--     This is the same line at which macOS starts hiding the menu bar,
--     so the two strips effectively tag-out.
local HIDE_AT_Y = 2
local function show_at_y()
  return (hs.screen.primaryScreen():frame().y) or 25
end

local function find_sketchybar()
  for _, p in ipairs({ "/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar" }) do
    if hs.fs.attributes(p) then return p end
  end
  return nil
end

local SKETCHYBAR = find_sketchybar()
if not SKETCHYBAR then return M end   -- sketchybar not installed; module is a no-op

-- Query the bar's current y_offset so we restore EXACTLY that value
-- when toggling back on. The rc currently sets y_offset=7 for vertical
-- centering, but if it changes there we don't have to track it here.
local function query_y_offset()
  local out = hs.execute(SKETCHYBAR .. " --query bar") or ""
  local n = out:match("\"y_offset\"%s*:%s*(-?%d+)")
  return tonumber(n) or 0
end

local SHOWN_OFFSET = query_y_offset()
local HIDDEN_OFFSET = -100
local shown = true

local function set_shown(s)
  if s == shown then return end
  shown = s
  hs.execute(SKETCHYBAR .. " --bar y_offset=" ..
    (s and tostring(SHOWN_OFFSET) or tostring(HIDDEN_OFFSET)))
end

M.timer = hs.timer.doEvery(0.1, function()
  local y = hs.mouse.absolutePosition().y
  if shown and y < HIDE_AT_Y then
    set_shown(false)
  elseif not shown and y >= show_at_y() then
    set_shown(true)
  end
end)

return M
