-- ~/.hammerspoon/cheatsheet.lua
-- Full-screen overlay of every Hyper-scheme keybinding.
-- Hyper+0 (Caps hold + 0) to toggle.  The background is fully invisible;
-- only frosted-glass cards float over the live desktop.
-- Edit `sections` to add or remove entries.

local M = {}

-- `color` is the accent line drawn across the top of each card.
-- Order: most-referenced content scans left-to-right, top-to-bottom.
local sections = {
  {
    color = "#60a5fa",                             -- blue   (OS windows)
    title = "Windows · yabai + skhd",
    rows  = {
      { "Hyper + H/J/K/L",     "Focus window  ←  ↓  ↑  →" },
      { "Meh + H/J/K/L",       "Swap window   ←  ↓  ↑  →" },
      { "Hyper + Return",       "Zoom fullscreen" },
      { "Hyper + F",            "Float / unfloat" },
      { "Hyper + R",            "Rotate space 90°" },
      { "Hyper + E",            "Balance  (equal splits)" },
      { "Hyper + 1 … 5",        "Jump to Space" },
    },
  },
  {
    color = "#fb923c",                             -- orange  (editor)
    title = "Neovim · leader ␣",
    rows  = {
      { "⟨spc⟩ h / j / k / l",  "Navigate splits" },
      { "⟨spc⟩ e",              "File explorer  (:Explore)" },
      { "⟨spc⟩ g",              "Git status" },
      { "⟨spc⟩ t",              "Run nearest test" },
      { "⟨spc⟩ ff / fg / fb",   "Find files / grep / buffers" },
      { "⟨spc⟩ ca / rn",        "Code action / rename  (LSP)" },
      { "gd / K",                "Go to definition / hover" },
    },
  },
  {
    color = "#34d399",                             -- emerald  (terminal)
    title = "tmux · prefix Ctrl-a",
    rows  = {
      { "Option + H/J/K/L",    "Select pane  (no prefix needed)" },
      { "Ctrl-a  |",           "Split right" },
      { "Ctrl-a  -",           "Split below" },
      { "Ctrl-a  r",           "Reload config" },
      { "Ctrl-a  Ctrl-a",      "Send Ctrl-a to program" },
    },
  },
  {
    color = "#a78bfa",                             -- violet   (the key)
    title = "Caps Lock",
    rows  = {
      { "Tap",                 "Escape  (vim / zsh-vim normal mode)" },
      { "Hold",                "Hyper  ⌃⌥⌘⇧" },
      { "Hold + Shift",        "Meh  ⌃⌥⌘  (yabai swap actions)" },
      { "Hyper + T / N",       "New terminal tab / window" },
      { "Hyper + ← → ↑ ↓",    "Snap  ½-left · ½-right · max · centre" },
      { "Hyper + 0",           "Toggle this cheatsheet" },
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

    /* Centre the grid on screen — body itself is invisible */
    .outer {
      width: 100%; height: 100%;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 10px;
      padding: 48px 64px;
    }

    .grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
      width: 100%;
      max-width: min(980px, 88vw);
    }

    /* Frosted-glass card — the only visible element */
    .card {
      background: rgba(8, 10, 15, 0.85);
      border: 1px solid rgba(255, 255, 255, 0.07);
      border-radius: 12px;
      padding: 16px 20px 18px;
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
      font-size: 10.5px;
      font-weight: 600;
      letter-spacing: 0.07em;
      text-transform: uppercase;
      color: var(--accent);
      margin-bottom: 13px;
    }

    table { width: 100%; border-collapse: collapse; }
    td    { padding: 5px 0; vertical-align: middle; }
    tr + tr td { border-top: 1px solid rgba(255, 255, 255, 0.045); }
    td.k  { white-space: nowrap; padding-right: 16px; width: 1%; }
    td.d  { font-size: 12px; color: rgba(221, 228, 238, 0.58); }

    kbd {
      display: inline-block;
      padding: 1px 6px;
      font: 11px "SF Mono", ui-monospace, Menlo, monospace;
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: 4px;
      line-height: 1.65;
      color: #dde4ee;
    }

    /* Ghost footer — just enough to know how to close */
    .footer {
      font-size: 10.5px;
      color: rgba(255, 255, 255, 0.18);
      letter-spacing: 0.04em;
    }
  ]]

  local parts = {}
  parts[#parts+1] = '<!doctype html><html><head><meta charset="utf-8"><style>'
    .. css .. '</style></head><body><div class="outer"><div class="grid">'

  for _, sec in ipairs(sections) do
    parts[#parts+1] = string.format(
      '<div class="card" style="--accent:%s"><div class="card-title">%s</div><table>',
      sec.color, sec.title
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
    '</div><div class="footer">Hyper+0 to close  ·  %s</div></div></body></html>',
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

-- Write a static copy to the Desktop each Hammerspoon load.
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
