-- Per-display autohide of the SketchyBar workspace strip.
--
-- For each display, hide that display's pills (by setting per-item
-- y_offset=-100) when the cursor approaches the top of THAT display.
-- macOS's auto-hide menu bar reveals on the same trigger, so the two
-- strips tag-out display-locally.
--
-- We toggle PER ITEM (not the bar's global y_offset) because sketchybar
-- only has one bar geometry. Each pill's y_offset is independent — and
-- items have an associated_display_mask, so y_offset=-100 only affects
-- that display's pills.
--
-- 100ms polling timer rather than an eventtap (eventtaps require
-- Input-Monitoring permission and weren't reliably receiving events in
-- practice). Cost per idle tick: one mouse position read + one
-- hs.screen lookup. Cost per transition: one yabai+sketchybar shell
-- call. Negligible.

local M = {}

local HIDE_AT_REL_Y    = 2     -- cursor inside top 2px of current display
local HIDDEN_Y_OFFSET  = -100  -- pill y_offset when hidden
local SHOWN_Y_OFFSET   = 0     -- pill y_offset when shown (natural)

local function find_sketchybar()
  for _, p in ipairs({ "/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar" }) do
    if hs.fs.attributes(p) then return p end
  end
  return nil
end
local SKETCHYBAR = find_sketchybar()
if not SKETCHYBAR then return M end

local function find_yabai()
  for _, p in ipairs({ "/opt/homebrew/bin/yabai", "/usr/local/bin/yabai" }) do
    if hs.fs.attributes(p) then return p end
  end
  return nil
end
local YABAI = find_yabai()
if not YABAI then return M end

-- Tracks the hidden/shown state per yabai display index so we don't
-- thrash sketchybar with redundant --set calls every tick.
local hidden_per_display = {}

-- Map an HS screen to a yabai display index by matching frame origin.
-- Yabai's display.frame uses the same absolute coordinates HS reports
-- for screen:fullFrame(), so equality on (x, y) is sufficient.
local function yabai_display_for_screen(screen)
  if not screen then return nil end
  local f = screen:fullFrame()
  local cmd = string.format(
    [[%s -m query --displays | /usr/bin/jq '[.[] | select(.frame.x == %g and .frame.y == %g) | .index] | first']],
    YABAI, f.x, f.y)
  local out = hs.execute(cmd)
  return tonumber(out)
end

-- Toggle all pills belonging to a yabai display.
local function set_display_hidden(yidx, hidden)
  if hidden_per_display[yidx] == hidden then return end
  hidden_per_display[yidx] = hidden
  local offset = hidden and HIDDEN_Y_OFFSET or SHOWN_Y_OFFSET
  -- Bulk update: build a single sketchybar command with all the --set
  -- pairs to avoid forking N subshells.
  local cmd = string.format(
    [[%s -m query --spaces | /usr/bin/jq -r '.[] | select(.display == %d) | .index' \
       | while read sid; do %s --set "space.$sid" y_offset=%d; done]],
    YABAI, yidx, SKETCHYBAR, offset)
  hs.execute(cmd)
end

M.timer = hs.timer.doEvery(0.1, function()
  local pos = hs.mouse.absolutePosition()
  local screen = hs.mouse.getCurrentScreen()
  if not screen then return end
  local rel_y = pos.y - screen:fullFrame().y   -- y within the current display

  -- Re-resolve yabai display once per tick (cheap; ~ms-fast yabai RPC).
  local yidx = yabai_display_for_screen(screen)
  if not yidx then return end

  -- Hysteresis on the cursor's CURRENT display:
  -- hide at the very top (relative y < 2);
  -- show again once the cursor drops below the menu-bar reserve.
  -- The menu-bar inset (frame.y - fullFrame.y) is ~32 on the notched
  -- built-in panel, ~24 on older displays, 0 on secondaries without
  -- a menu bar.
  local menu_bar_inset = screen:frame().y - screen:fullFrame().y
  if rel_y < HIDE_AT_REL_Y then
    set_display_hidden(yidx, true)
  elseif rel_y >= menu_bar_inset then
    set_display_hidden(yidx, false)
  end

  -- Any OTHER display the cursor isn't on right now should be in the
  -- shown state — otherwise it could stay hidden indefinitely after
  -- the cursor jumps from its top into another display.
  for other_yidx, hidden in pairs(hidden_per_display) do
    if other_yidx ~= yidx and hidden then
      set_display_hidden(other_yidx, false)
    end
  end
end)

return M
