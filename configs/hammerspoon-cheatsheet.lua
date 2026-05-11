-- ~/.hammerspoon/cheatsheet.lua
-- Toggle a semi-transparent fullscreen overlay listing every Hyper-scheme
-- keybinding. Bound to Hyper+0 (hold Caps + 0). Click-through: keystrokes
-- pass to the underlying app, so you can keep typing while the cheatsheet
-- is on screen. Toggle off with another Hyper+0.
-- Edit the `sections` table to add/remove entries.

local M = {}

local sections = {
  {
    title = "macOS · Window Manager (yabai, driven by skhd)",
    rows  = {
      { "Hyper + H / J / K / L",         "Focus window  left / down / up / right" },
      { "Hyper + Shift + H / J / K / L", "Swap window   left / down / up / right" },
      { "Hyper + Return",                "Toggle zoom-fullscreen" },
      { "Hyper + F",                     "Toggle float (window stays where it is, becomes unmanaged)" },
      { "Hyper + R",                     "Rotate space 90°" },
      { "Hyper + E",                     "Balance space (equal splits)" },
      { "Hyper + 1 … 5",                 "Jump to Space 1 … 5" },
    },
  },
  {
    title = "macOS · Caps Lock semantics + Hammerspoon",
    rows  = {
      { "Caps Lock (tap)",         "Escape — exit vim/zsh-vim insert mode" },
      { "Caps Lock (held)",        "Hyper = ⌃⌥⌘⇧" },
      { "Caps Lock + Shift",       "Meh   = ⌃⌥⌘   (used for `swap` actions)" },
      { "Hyper + T",               "New terminal tab" },
      { "Hyper + N",               "New terminal window" },
      { "Hyper + ← / → / ↑ / ↓",   "SIP-safe snap: half-left / half-right / max / centre" },
      { "Hyper + 0",               "Toggle this cheatsheet" },
      { "~/Desktop/Hyper-Keys.html","Static reference, regenerated each Hammerspoon load" },
    },
  },
  {
    title = "tmux · prefix = Ctrl+a  ·  pane nav = Option+hjkl",
    rows  = {
      { "Option + h / j / k / l", "Select pane  left / down / up / right  (no prefix!)" },
      { "Ctrl-a  |   /  -",       "Split pane right / below (opens in current dir)" },
      { "Ctrl-a  r",              "Reload ~/.tmux.conf" },
      { "Ctrl-a  Ctrl-a",         "Send literal Ctrl-a to the inner program" },
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
  -- Background is semi-transparent so the windows underneath stay legible.
  -- Tune the alpha here; 0.78 reads well on dark terminals.
  local css = [[
    :root {
      --bg: rgba(13, 17, 23, 0.78);
      --panel: rgba(22, 27, 34, 0.92);
      --border: #30363d;
      --text: #e6edf3;
      --muted: #8b949e;
      --accent: #79c0ff;
      --kbd-bg: rgba(33, 38, 45, 0.95);
      --kbd-border: #444c56;
    }
    * { box-sizing: border-box; }
    html, body { height: 100%; }
    body {
      margin: 0; padding: 36px 48px;
      font: 13.5px -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui;
      background: var(--bg); color: var(--text);
      -webkit-font-smoothing: antialiased;
      text-shadow: 0 1px 2px rgba(0,0,0,0.6);
    }
    h1 {
      margin: 0 0 18px; font-size: 22px; font-weight: 600;
      display: flex; align-items: center; gap: 8px;
    }
    h1 .pill {
      font-size: 11px; padding: 2px 8px; border-radius: 999px;
      background: #1f6feb55; color: var(--accent); font-weight: 500;
    }
    .grid {
      display: grid; gap: 18px;
      grid-template-columns: repeat(auto-fit, minmax(420px, 1fr));
    }
    .section {
      background: var(--panel); border: 1px solid var(--border);
      border-radius: 10px; padding: 16px 20px;
      backdrop-filter: blur(2px);
    }
    .section h2 {
      margin: 0 0 12px; font-size: 13px; font-weight: 600;
      color: var(--accent); letter-spacing: 0.2px;
    }
    table { width: 100%; border-collapse: collapse; }
    td { padding: 6px 0; vertical-align: top; }
    td.k { white-space: nowrap; padding-right: 16px; width: 1%; }
    td.d { color: var(--muted); }
    kbd {
      display: inline-block; padding: 1px 7px; font-size: 11.5px;
      font-family: "SF Mono", ui-monospace, Menlo, monospace;
      background: var(--kbd-bg); border: 1px solid var(--kbd-border);
      border-radius: 4px; line-height: 1.5; color: var(--text);
    }
    .hint {
      position: fixed; bottom: 14px; right: 20px;
      color: var(--muted); font-size: 11px;
    }
  ]]

  local parts = {}
  parts[#parts+1] = '<!doctype html><html><head><meta charset="utf-8"><style>' .. css .. '</style></head><body>'
  parts[#parts+1] = '<h1>Hyper Key Cheatsheet <span class="pill">Caps Lock — tap = F13 (tmux) · hold = Hyper ⌃⌥⌘⇧</span></h1>'
  parts[#parts+1] = '<div class="grid">'
  for _, sec in ipairs(sections) do
    parts[#parts+1] = '<div class="section"><h2>' .. sec.title .. '</h2><table>'
    for _, row in ipairs(sec.rows) do
      parts[#parts+1] = ('<tr><td class="k"><kbd>%s</kbd></td><td class="d">%s</td></tr>')
        :format(row[1], row[2])
    end
    parts[#parts+1] = '</table></div>'
  end
  local stamp = os.date('%Y-%m-%d %H:%M')
  parts[#parts+1] = '</div><div class="hint">Source: ~/.hammerspoon/cheatsheet.lua · Refreshed: ' .. stamp .. '</div></body></html>'
  return table.concat(parts)
end

-- Toggle: pressing the binding again closes the overlay.
function M.toggle()
  if M.view then
    M.view:delete()
    M.view = nil
    return
  end

  -- Cover the full active screen (including menu bar / dock area).
  local screen = hs.screen.mainScreen():fullFrame()
  local rect = hs.geometry.rect(screen.x, screen.y, screen.w, screen.h)

  local prefs = { developerExtrasEnabled = false }
  M.view = hs.webview.new(rect, prefs)
    :windowStyle({ "borderless", "nonactivating" })  -- no chrome, no focus steal
    :level(hs.drawing.windowLevels.modalPanel)
    :transparent(true)                                -- honor body's rgba bg
    :allowTextEntry(false)
    :shadow(false)
    :html(render_html())
    :show()

  -- Don't capture keyboard events — let keystrokes pass through to whatever
  -- the user was using. Toggling off is via Hyper+0 (the global hotkey).
  pcall(function() M.view:passthroughKeyboardEvents(true) end)
end

-- Dump a static copy of the cheatsheet to the Desktop. Idempotent: rewritten
-- each Hammerspoon load, so the file always reflects the current sections.
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
