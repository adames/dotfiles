-- ~/.hammerspoon/cheatsheet.lua
-- Full-screen overlay of keybindings for this machine's setup.
-- Hyper+0 (Caps hold + 0) to toggle.  Background is fully invisible;
-- only three frosted-glass cards float over the live desktop.
-- Edit `sections` to add or remove entries — no logic to break.

local M = {}

-- Three sections map to the three layers of the workspace:
--   OS windows → terminal multiplexer → editor
-- `color` = accent line at the top of the card.
-- `sub`   = ghost subtitle under the section title (explains the modifier).
local sections = {
  {
    color = "#60a5fa",
    title = "Windows",
    sub   = "Hyper = Caps hold  ·  Meh = Caps+Shift  ·  yabai + skhd",
    rows  = {
      { "Hyper + H/J/K/L",    "Focus window  ←  ↓  ↑  →" },
      { "Meh + H/J/K/L",      "Swap window   ←  ↓  ↑  →" },
      { "Hyper + ← → ↑ ↓",   "Snap  ½-left · ½-right · max · centre" },
      { "Hyper + Return",      "Zoom fullscreen" },
      { "Hyper + F",           "Float / unfloat" },
      { "Hyper + E / R",       "Balance space / rotate 90°" },
      { "Hyper + 1 … 5",       "Jump to Space" },
      { "Hyper + T / N",       "New terminal tab / window" },
    },
  },
  {
    color = "#34d399",
    title = "Terminal",
    sub   = "Option = no-prefix tmux  ·  Ctrl-a = prefix (SSH fallback)",
    rows  = {
      { "Option + H/J/K/L",   "Select pane  ←  ↓  ↑  →" },
      { "Option + V",          "Split right  (vertical divider)" },
      { "Option + S",          "Split below" },
      { "Option + R",          "Reload config" },
      { "Ctrl-a  [",           "Scroll / copy mode  (q to exit)" },
      { "Ctrl-a  Z",           "Zoom pane  (toggle)" },
      { "Ctrl-a  D",           "Detach session" },
      { "Ctrl-a  Ctrl-a",      "Send Ctrl-a to the inner program" },
    },
  },
  {
    color = "#fb923c",
    title = "Editor",
    sub   = "Caps tap = Escape  ·  ⟨spc⟩ = Space leader  ·  Neovim",
    rows  = {
      { "⟨spc⟩ h/j/k/l",      "Navigate splits" },
      { "⟨spc⟩ ff / fg / fb", "Find files / live grep / buffers" },
      { "⟨spc⟩ ca / rn",      "Code action / rename  (LSP)" },
      { "gd / gr / K",         "Definition / references / hover" },
      { "⟨spc⟩ e / g / t",    "Explorer / git / test" },
      { "Ctrl-o / Ctrl-i",     "Jump back / forward in jump list" },
      { "* / #",               "Search word under cursor  fwd / bwd" },
      { "ci⟨x⟩ / ca⟨x⟩",     "Change inside / around text object" },
    },
  },
}

local function render_html()
  local css = [[
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    html, body {
      width: 100%; height: 100%;
      background: transparent;
      font: 13px -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui;
      color: #dde4ee;
      -webkit-font-smoothing: antialiased;
    }

    .outer {
      width: 100%; height: 100%;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 10px;
      padding: 52px 56px;
    }

    /* Three equal columns — one per workspace layer */
    .grid {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 14px;
      width: 100%;
      max-width: min(1180px, 92vw);
    }

    /* Frosted-glass card — the only visible element on screen */
    .card {
      background: rgba(8, 10, 15, 0.85);
      border: 1px solid rgba(255, 255, 255, 0.07);
      border-radius: 12px;
      padding: 18px 22px 20px;
      backdrop-filter: blur(20px) saturate(180%);
      -webkit-backdrop-filter: blur(20px) saturate(180%);
      position: relative;
      overflow: hidden;
    }

    /* Coloured accent line at the top of each card */
    .card::before {
      content: '';
      position: absolute;
      top: 0; left: 0; right: 0;
      height: 2px;
      background: var(--accent);
    }

    .card-title {
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--accent);
      margin-bottom: 4px;
    }

    /* Ghost subtitle: explains the modifier key for this card */
    .card-sub {
      font-size: 10px;
      color: rgba(255, 255, 255, 0.28);
      letter-spacing: 0.02em;
      margin-bottom: 14px;
    }

    table { width: 100%; border-collapse: collapse; }
    td    { padding: 5px 0; vertical-align: middle; }
    tr + tr td { border-top: 1px solid rgba(255, 255, 255, 0.045); }
    td.k  { white-space: nowrap; padding-right: 16px; width: 1%; }
    td.d  { font-size: 11.5px; color: rgba(221, 228, 238, 0.58); }

    kbd {
      display: inline-block;
      padding: 1px 6px;
      font: 10.5px "SF Mono", ui-monospace, Menlo, monospace;
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: 4px;
      line-height: 1.65;
      color: #dde4ee;
    }

    /* Ghost footer */
    .footer {
      font-size: 10px;
      color: rgba(255, 255, 255, 0.16);
      letter-spacing: 0.05em;
    }
  ]]

  local parts = {}
  parts[#parts+1] = '<!doctype html><html><head><meta charset="utf-8"><style>'
    .. css .. '</style></head><body><div class="outer"><div class="grid">'

  for _, sec in ipairs(sections) do
    parts[#parts+1] = string.format(
      '<div class="card" style="--accent:%s">'
        .. '<div class="card-title">%s</div>'
        .. '<div class="card-sub">%s</div>'
        .. '<table>',
      sec.color, sec.title, sec.sub
    )
    for _, row in ipairs(sec.rows) do
      parts[#parts+1] = string.format(
        '<tr><td class="k"><kbd>%s</kbd></td><td class="d">%s</td></tr>',
        row[1], row[2]
      )
    end
    parts[#parts+1] = '</table></div>'
  end

  parts[#parts+1] = string.format(
    '</div><div class="footer">HYPER + 0 TO CLOSE  ·  %s</div></div></body></html>',
    os.date('%H:%M')
  )
  return table.concat(parts)
end

-- Toggle: pressing the binding again closes the overlay.
function M.toggle()
  if M.view then
    M.view:delete()
    M.view = nil
    return
  end

  local screen = hs.screen.mainScreen():fullFrame()
  local rect   = hs.geometry.rect(screen.x, screen.y, screen.w, screen.h)

  M.view = hs.webview.new(rect, { developerExtrasEnabled = false })
    :windowStyle({ "borderless", "nonactivating" })
    :level(hs.drawing.windowLevels.modalPanel)
    :transparent(true)
    :allowTextEntry(false)
    :shadow(false)
    :html(render_html())
    :show()

  pcall(function() M.view:passthroughKeyboardEvents(true) end)
end

-- Write a static copy to the Desktop on every Hammerspoon load.
function M.dump_to_desktop()
  local path = os.getenv("HOME") .. "/Desktop/Hyper-Keys.html"
  local f, err = io.open(path, "w")
  if not f then
    print("cheatsheet: could not write " .. path .. ": " .. tostring(err))
    return
  end
  f:write(render_html())
  f:close()
end

M.dump_to_desktop()

return M
