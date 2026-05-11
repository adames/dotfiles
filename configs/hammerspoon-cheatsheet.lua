-- ~/.hammerspoon/cheatsheet.lua
-- Full-screen overlay of keybindings for this machine's setup.
-- Caps Lock + 0 (held) to toggle.  Background is fully invisible;
-- only three frosted-glass cards float over the live desktop.
-- Edit `sections` to add or remove entries — no logic to break.

local M = {}

local sections = {
  {
    color = "#60a5fa",
    title = "Windows",
    sub   = "yabai  ·  skhd  ·  Hammerspoon",
    rows  = {
      { "caps lock + hjkl",          "focus window  ←  ↓  ↑  →" },
      { "caps lock + shift + hjkl",  "swap window   ←  ↓  ↑  →" },
      { "caps lock + ← → ↑ ↓",      "snap  ½-left · ½-right · max · centre" },
      { "caps lock + return",         "zoom fullscreen" },
      { "caps lock + f",              "float / unfloat" },
      { "caps lock + e / r",          "balance space / rotate 90°" },
      { "caps lock + 1…5",           "jump to space" },
      { "caps lock + t / n",          "new terminal tab / window" },
    },
  },
  {
    color = "#34d399",
    title = "Terminal",
    sub   = "tmux  ·  prefix = ctrl-space",
    rows  = {
      { "ctrl-space  hjkl",         "select pane  ←  ↓  ↑  →" },
      { "ctrl-space  v",            "split right" },
      { "ctrl-space  s",            "split below" },
      { "ctrl-space  z",            "zoom pane  (toggle)" },
      { "ctrl-space  d",            "detach session" },
      { "ctrl-space  r",            "reload config" },
      { "ctrl-space  [",            "scroll / copy mode  (q to exit)" },
      { "ctrl-space  ctrl-space",   "send ctrl-space to program" },
    },
  },
  {
    color = "#fb923c",
    title = "Editor",
    sub   = "neovim  ·  caps lock tap = escape  ·  built-in defaults only",
    rows  = {
      { "ctrl-w hjkl",       "navigate splits" },
      { "ctrl-w v / s",      "split right / below  (mirrors tmux)" },
      { "gd / K",            "definition / hover  (lsp, auto-bound on attach)" },
      { "grn / gra",         "rename / code action  (lsp, nvim 0.10+)" },
      { "ctrl-o / ctrl-i",   "jump back / forward in jump list" },
      { "* / #",             "search word under cursor  fwd / bwd" },
      { "gcc / gc⟨motion⟩",  "toggle comment line / motion  (nvim 0.10+)" },
      { "ci⟨x⟩ / ca⟨x⟩",    "change inside / around text object" },
    },
  },
}

local function render_html()
  local css = [[
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    html, body {
      width: 100%; height: 100%;
      background: transparent;
      font: 15px -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui;
      color: #dde4ee;
      -webkit-font-smoothing: antialiased;
    }

    .outer {
      width: 100%; height: 100%;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 12px;
      padding: 52px 48px;
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 16px;
      width: 100%;
      max-width: min(1300px, 96vw);
    }

    .card {
      background: rgba(8, 10, 15, 0.85);
      border: 1px solid rgba(255, 255, 255, 0.07);
      border-radius: 12px;
      padding: 20px 22px 22px;
      backdrop-filter: blur(20px) saturate(180%);
      -webkit-backdrop-filter: blur(20px) saturate(180%);
      position: relative;
      overflow: hidden;
    }

    .card::before {
      content: '';
      position: absolute;
      top: 0; left: 0; right: 0;
      height: 2px;
      background: var(--accent);
    }

    .card-title {
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--accent);
      margin-bottom: 4px;
    }

    .card-sub {
      font-size: 11.5px;
      color: rgba(255, 255, 255, 0.28);
      letter-spacing: 0.01em;
      margin-bottom: 16px;
    }

    table { width: 100%; border-collapse: collapse; }
    td    { padding: 6px 0; vertical-align: top; }
    tr + tr td { border-top: 1px solid rgba(255, 255, 255, 0.045); }
    td.k  { white-space: nowrap; padding-right: 14px; width: 1%; }
    td.d  { font-size: 13px; color: rgba(221, 228, 238, 0.58); }

    /* nowrap on kbd itself prevents the chip from breaking mid-label */
    kbd {
      display: inline-block;
      white-space: nowrap;
      padding: 2px 7px;
      font: 11.5px "SF Mono", ui-monospace, Menlo, monospace;
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: 5px;
      line-height: 1.6;
      color: #dde4ee;
    }

    .footer {
      font-size: 11px;
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
    '</div><div class="footer">CAPS LOCK + 0 TO CLOSE  ·  %s</div></div></body></html>',
    os.date('%H:%M')
  )
  return table.concat(parts)
end

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
