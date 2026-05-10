-- ~/.hammerspoon/cheatsheet.lua
-- Toggle an overlay listing every Hyper-scheme keybinding. Bound to Hyper+/.
-- Edit the `sections` table to add/remove entries.

local M = {}

local sections = {
  {
    title = "macOS · Window Manager (Hyper → skhd → yabai)",
    rows  = {
      { "Hyper + H / J / K / L",         "Focus window  left / down / up / right" },
      { "Hyper + Shift + H / J / K / L", "Swap window   left / down / up / right" },
      { "Hyper + Return",                "Toggle zoom-fullscreen" },
      { "Hyper + F",                     "Toggle float (centred 50% × 50%)" },
      { "Hyper + R",                     "Rotate space 90°" },
      { "Hyper + E",                     "Balance space (equal splits)" },
      { "Hyper + 1 … 5",                 "Jump to Space 1 … 5" },
    },
  },
  {
    title = "macOS · Hammerspoon",
    rows  = {
      { "Caps Lock (tap)",     "Escape  (Karabiner)" },
      { "Caps Lock (held)",    "Hyper = ⌃⌥⌘⇧" },
      { "Caps Lock + Shift",   "Meh   = ⌃⌥⌘   (used for `swap` actions)" },
      { "Hyper + T",           "New terminal tab" },
      { "Hyper + N",           "New terminal window" },
      { "Hyper + ← / → / ↑ / ↓", "SIP-safe snap: half-left / half-right / max / centre" },
      { "Hyper + /  or  Hyper + 0", "Show / hide this cheatsheet" },
      { "double-click ~/Desktop/Hyper-Keys.html", "Static reference, regenerated each Hammerspoon load" },
    },
  },
  {
    title = "tmux · prefix = Ctrl-A",
    rows  = {
      { "C-a  h / j / k / l", "Select pane  left / down / up / right" },
      { "C-a  |   /  -",      "Split pane horizontal / vertical" },
      { "C-a  r",             "Reload ~/.tmux.conf" },
      { "C-a  C-a",           "Send literal C-a to inner program" },
    },
  },
  {
    title = "Neovim · leader = ␣ (Space)",
    rows  = {
      { "<leader> h / j / k / l", "Move between window splits" },
      { "<leader> e",             "File explorer  (:Explore)" },
      { "<leader> g",             "Git status     (fugitive / gitsigns)" },
      { "<leader> t",             "Run nearest test (vim-test / neotest)" },
      { "<leader> ff / fg / fb",  "Find files / grep / buffers (fzf-lua)" },
      { "<leader> ca / rn",       "LSP code-action / rename" },
      { "gd / K",                 "LSP go-to-def / hover docs" },
    },
  },
}

local function render_html()
  local css = [[
    :root {
      --bg: #0d1117;
      --panel: #161b22;
      --border: #30363d;
      --text: #e6edf3;
      --muted: #8b949e;
      --accent: #79c0ff;
      --kbd-bg: #21262d;
      --kbd-border: #444c56;
    }
    * { box-sizing: border-box; }
    html, body { height: 100%; }
    body {
      margin: 0; padding: 28px 32px;
      font: 13.5px -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui;
      background: var(--bg); color: var(--text);
      -webkit-font-smoothing: antialiased;
    }
    h1 {
      margin: 0 0 4px; font-size: 20px; font-weight: 600;
      display: flex; align-items: center; gap: 8px;
    }
    h1 .pill {
      font-size: 11px; padding: 2px 8px; border-radius: 999px;
      background: #1f6feb33; color: var(--accent); font-weight: 500;
    }
    .sub { color: var(--muted); margin: 0 0 22px; font-size: 12px; }
    .grid {
      display: grid; gap: 16px;
      grid-template-columns: repeat(auto-fit, minmax(360px, 1fr));
    }
    .section {
      background: var(--panel); border: 1px solid var(--border);
      border-radius: 8px; padding: 14px 16px;
    }
    .section h2 {
      margin: 0 0 10px; font-size: 13px; font-weight: 600;
      color: var(--accent); letter-spacing: 0.2px;
    }
    table { width: 100%; border-collapse: collapse; }
    td { padding: 5px 0; vertical-align: top; }
    td.k { white-space: nowrap; padding-right: 14px; width: 1%; }
    td.d { color: var(--muted); }
    kbd {
      display: inline-block; padding: 1px 6px; font-size: 11.5px;
      font-family: "SF Mono", ui-monospace, Menlo, monospace;
      background: var(--kbd-bg); border: 1px solid var(--kbd-border);
      border-radius: 4px; line-height: 1.5; color: var(--text);
    }
    .hint {
      position: fixed; bottom: 12px; right: 16px;
      color: var(--muted); font-size: 11px;
    }
  ]]

  local parts = {}
  parts[#parts+1] = '<!doctype html><html><head><meta charset="utf-8"><style>' .. css .. '</style></head><body>'
  parts[#parts+1] = '<h1>Hyper Key Cheatsheet <span class="pill">Caps Lock = ⌃⌥⌘⇧</span></h1>'
  parts[#parts+1] = '<p class="sub">Toggle with <kbd>Hyper</kbd> + <kbd>/</kbd> · Dismiss with <kbd>Esc</kbd></p>'
  parts[#parts+1] = '<div class="grid">'
  for _, sec in ipairs(sections) do
    parts[#parts+1] = '<div class="section"><h2>' .. sec.title .. '</h2><table>'
    for _, row in ipairs(sec.rows) do
      parts[#parts+1] = ('<tr><td class="k"><kbd>%s</kbd></td><td class="d">%s</td></tr>')
        :format(row[1], row[2])
    end
    parts[#parts+1] = '</table></div>'
  end
  parts[#parts+1] = '</div><div class="hint">~/.hammerspoon/cheatsheet.lua</div></body></html>'
  return table.concat(parts)
end

-- Toggle: pressing the binding again closes the overlay.
function M.toggle()
  if M.view then
    M.view:delete()
    M.view = nil
    if M.escTap then M.escTap:stop(); M.escTap = nil end
    return
  end

  local screen = hs.screen.mainScreen():frame()
  local w, h = math.min(960, screen.w - 80), math.min(640, screen.h - 80)
  local rect = hs.geometry.rect(
    screen.x + (screen.w - w) / 2,
    screen.y + (screen.h - h) / 2,
    w, h
  )

  local prefs = { developerExtrasEnabled = false }
  M.view = hs.webview.new(rect, prefs)
    :windowStyle({ "titled", "closable", "nonactivating" })
    :windowTitle("Hyper Key Cheatsheet")
    :level(hs.drawing.windowLevels.modalPanel)
    :allowTextEntry(false)
    :shadow(true)
    :html(render_html())
    :show()

  -- Dismiss on Escape regardless of focus.
  M.escTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    if e:getKeyCode() == hs.keycodes.map.escape then
      M.toggle()
      return true
    end
    return false
  end):start()
end

-- Dump a static copy of the cheatsheet to the Desktop, so a non-key-savvy user
-- can open it without remembering any binding. Idempotent: rewritten each time
-- Hammerspoon loads, so the file always reflects the current `sections` table.
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

-- Render at load time so the desktop file is always fresh.
M.dump_to_desktop()

return M
