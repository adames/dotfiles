-- Caps + 0 overlay. Edit `sections`; no logic to break.
-- Use ⟨x⟩ (unicode) for placeholders so HTML doesn't swallow them.

local M = {}

local sections = {
  -- ── Windows ───────────────────────────────────────────────────────────────
  {
    color = "#60a5fa",
    title = "Windows",
    sub   = "yabai · skhd · Hammerspoon",
    rows  = {
      { "caps + hjkl",         "focus window  ←  ↓  ↑  →" },
      { "caps + shift + hjkl", "swap window   ←  ↓  ↑  →" },
      { "caps + return",       "zoom fullscreen (toggle)" },
      { "caps + f",            "float / unfloat window" },
      { "caps + e",            "balance space" },
      { "caps + r",            "rotate space 90°" },
      { "caps + 1…5",          "jump to space" },
      { "caps + ← →",         "snap ½-left / ½-right  (SIP-safe)" },
      { "caps + ↑ ↓",         "maximise / centre 50%  (SIP-safe)" },
      { "caps + t",            "new terminal tab" },
      { "caps + n",            "new terminal window" },
      { "caps + 0",            "toggle this cheatsheet" },
    },
  },
  -- ── Tmux ──────────────────────────────────────────────────────────────────
  {
    color = "#34d399",
    title = "Tmux",
    sub   = "prefix = ctrl-space",
    rows  = {
      { "C-space  hjkl",       "select pane  ←  ↓  ↑  →" },
      { "C-space  v / s",      "split right / below  (mirrors vim Ctrl-w)" },
      { "C-space  z",          "zoom pane (toggle)" },
      { "C-space  d",          "detach session" },
      { "C-space  r",          "reload tmux.conf" },
      { "C-space  [",          "copy / scroll mode  (q to exit)" },
      { "C-space  f",          "sessionizer — fzf pick → switch/create session" },
      { "C-space  c",          "new window" },
      { "C-space  n / p",      "next / prev window" },
      { "C-space  0…9",        "go to window N" },
      { "C-space  x",          "kill pane" },
      { "C-space  $",          "rename current session" },
      { "C-space  C-space",    "send literal C-space to program" },
    },
  },
  -- ── Vim motion ────────────────────────────────────────────────────────────
  {
    color = "#fb923c",
    title = "Vim · Motion",
    sub   = "neovim · cursor & jumps",
    rows  = {
      { "h j k l",             "← ↓ ↑ →" },
      { "w  b  e",             "word: next start / prev start / next end" },
      { "0  ^  $",             "line: start / first nonblank / end" },
      { "gg  G",               "file: top / bottom" },
      { "{  }",                "paragraph: back / forward" },
      { "f⟨x⟩  F⟨x⟩",          "find char in line: forward / back" },
      { "t⟨x⟩  T⟨x⟩",          "till char in line: forward / back" },
      { "%",                   "matching ( [ {" },
      { "/pat   n / N",        "search forward · next / prev match" },
      { "*  #",                "search word under cursor: fwd / back" },
      { "ctrl-o  ctrl-i",      "jumplist: back / forward" },
      { "m⟨a-z⟩   '⟨a-z⟩",    "set mark / jump to mark line" },
    },
  },
  -- ── Vim edit ──────────────────────────────────────────────────────────────
  {
    color = "#f97316",
    title = "Vim · Edit",
    sub   = "neovim · change & yank",
    rows  = {
      { "i  a   I  A",          "insert: before / after / line-start / line-end" },
      { "o  O",                  "open line: below / above" },
      { "cc  dd  yy",            "change / delete / yank whole line" },
      { "ci⟨x⟩  ca⟨x⟩",          "change inside / around  (\" ' ( [ { t p)" },
      { "p  P",                  "paste: after / before" },
      { "\"0p",                  "paste last yank  (skip delete register)" },
      { "u   ctrl-r",            "undo / redo" },
      { ".",                     "repeat last change" },
      { "ctrl-a  ctrl-x",        "increment / decrement number" },
      { "q⟨x⟩ … q     @⟨x⟩",   "record macro / replay" },
      { ":%s/foo/bar/g",         "replace all in buffer  (add c for confirm)" },
      { "> >    < <",            "indent / dedent line" },
    },
  },
  -- ── Neovim plugins (LSP + find + diagnostics) ─────────────────────────────
  {
    color = "#f472b6",
    title = "Neovim · LSP & Find",
    sub   = "leader = space  ·  pyright + ruff attach to *.py",
    rows  = {
      { "gd   gr",               "go to definition / references" },
      { "K",                     "hover docs" },
      { "⟨leader⟩ ca",            "code action" },
      { "⟨leader⟩ rn",            "rename symbol" },
      { "⟨leader⟩ =",             "format buffer  (auto-runs ruff on :w for *.py)" },
      { "⟨leader⟩ ff",            "fzf files" },
      { "⟨leader⟩ fg",            "fzf live grep" },
      { "⟨leader⟩ fb",            "fzf buffers" },
      { "]d   [d",               "next / prev diagnostic" },
      { "ctrl-w  v / s",         "split right / below" },
      { "ctrl-w  hjkl",          "navigate splits" },
      { ":bn  :bp  :bd",         "next / prev / delete buffer" },
    },
  },
  -- ── Python dev (debug + test) ─────────────────────────────────────────────
  {
    color = "#facc15",
    title = "Python · Debug & Test",
    sub   = "nvim-dap (debugpy)  ·  neotest (pytest)",
    rows  = {
      { "⟨leader⟩ db",            "toggle breakpoint" },
      { "⟨leader⟩ dc",            "continue" },
      { "⟨leader⟩ do",            "step over" },
      { "⟨leader⟩ di",            "step into" },
      { "⟨leader⟩ du",            "step out" },
      { "⟨leader⟩ dr",            "open REPL" },
      { "⟨leader⟩ dx",            "terminate session" },
      { "⟨leader⟩ dU",            "toggle DAP UI" },
      { "⟨leader⟩ tn",            "test nearest" },
      { "⟨leader⟩ tf",            "test file" },
      { "⟨leader⟩ tl",            "run last test" },
      { "⟨leader⟩ ts",            "toggle test summary panel" },
      { "⟨leader⟩ to",            "open test output" },
      { "⟨leader⟩ td",            "debug nearest test  (drops to dap)" },
    },
  },
  -- ── Shell ─────────────────────────────────────────────────────────────────
  {
    color = "#22d3ee",
    title = "Shell",
    sub   = "zsh · vi mode · fzf · zoxide",
    rows  = {
      { "ctrl-r",                "fzf history search" },
      { "ctrl-t",                "fzf file picker (insert path)" },
      { "alt-c",                 "fzf cd into subdir" },
      { "⟨pat⟩**<tab>",          "fzf completion on the current word" },
      { "esc",                   "enter vi-mode normal (then hjkl, /, w, b, …)" },
      { "z ⟨pat⟩",                "zoxide: jump to most-frecent matching dir" },
      { "zi",                    "zoxide: interactive picker" },
      { "rg ⟨pat⟩",               "ripgrep — uses ~/.ripgreprc defaults" },
      { "fd ⟨pat⟩",               "fd — fast find replacement" },
      { "direnv allow",          "trust this dir's .envrc on first entry" },
    },
  },
  -- ── Git ───────────────────────────────────────────────────────────────────
  {
    color = "#fb7185",
    title = "Git",
    sub   = "aliases · delta pager · gh CLI",
    rows  = {
      { "gs  ga  gc",            "status / add / commit  (zsh aliases)" },
      { "gp  gpl",               "push / pull" },
      { "git diff / log / show", "delta-rendered, side-by-side off" },
      { "n / N  (in pager)",     "delta: next / prev section" },
      { "q       (in pager)",    "exit pager" },
      { "gh pr create",          "open PR for current branch" },
      { "gh pr checkout ⟨n⟩",     "check out PR by number" },
      { "gh pr view --web",      "open PR in browser" },
      { "gh run watch",          "tail latest workflow run" },
    },
  },
}

local function render_html()
  local css = [[
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    html, body {
      width: 100%; height: 100%;
      background: transparent;
      font: 14px -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui;
      color: #dde4ee;
      -webkit-font-smoothing: antialiased;
    }

    .outer {
      width: 100%; height: 100%;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: flex-start;
      gap: 12px;
      padding: 36px 40px 24px;
    }

    .banner {
      display: flex;
      gap: 28px;
      align-items: center;
      font-size: 11.5px;
      letter-spacing: 0.05em;
      color: rgba(255, 255, 255, 0.5);
      background: rgba(8, 10, 15, 0.7);
      backdrop-filter: blur(20px) saturate(180%);
      -webkit-backdrop-filter: blur(20px) saturate(180%);
      border: 1px solid rgba(255, 255, 255, 0.06);
      border-radius: 999px;
      padding: 8px 22px;
      margin-bottom: 6px;
    }
    .banner b { color: #c084fc; font-weight: 600; }
    .banner .b-sep { color: rgba(255, 255, 255, 0.12); }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(290px, 1fr));
      gap: 14px;
      width: 100%;
      max-width: min(1720px, 97vw);
      align-items: start;
    }

    .card {
      background: rgba(8, 10, 15, 0.85);
      border: 1px solid rgba(255, 255, 255, 0.07);
      border-radius: 12px;
      padding: 18px 20px 20px;
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
      font-size: 11.5px;
      font-weight: 700;
      letter-spacing: 0.09em;
      text-transform: uppercase;
      color: var(--accent);
      margin-bottom: 3px;
    }

    .card-sub {
      font-size: 11px;
      color: rgba(255, 255, 255, 0.30);
      letter-spacing: 0.01em;
      margin-bottom: 12px;
    }

    table { width: 100%; border-collapse: collapse; }
    td    { padding: 5px 0; vertical-align: top; }
    tr + tr td { border-top: 1px solid rgba(255, 255, 255, 0.045); }
    td.k  { white-space: nowrap; padding-right: 12px; width: 1%; }
    td.d  { font-size: 12.5px; color: rgba(221, 228, 238, 0.62); }

    kbd {
      display: inline-block;
      white-space: nowrap;
      padding: 2px 7px;
      font: 11px "SF Mono", ui-monospace, Menlo, monospace;
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: 5px;
      line-height: 1.6;
      color: #dde4ee;
    }

    .footer {
      font-size: 11px;
      color: rgba(255, 255, 255, 0.18);
      letter-spacing: 0.05em;
      margin-top: 4px;
    }
  ]]

  local parts = {}
  parts[#parts+1] = '<!doctype html><html><head><meta charset="utf-8"><style>'
    .. css .. '</style></head><body><div class="outer">'

  -- Hyper contract banner across the top
  parts[#parts+1] = ''
    .. '<div class="banner">'
    .. '<span><kbd>caps</kbd> <b>tap</b> → Esc</span>'
    .. '<span class="b-sep">·</span>'
    .. '<span><kbd>caps</kbd> <b>hold</b> → Hyper (⌃⌥⌘⇧)</span>'
    .. '<span class="b-sep">·</span>'
    .. '<span><kbd>caps</kbd> + <kbd>shift</kbd> <b>hold</b> → Meh (⌃⌥⌘)</span>'
    .. '<span class="b-sep">·</span>'
    .. '<span>leader = <kbd>space</kbd></span>'
    .. '</div>'

  parts[#parts+1] = '<div class="grid">'

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

return M
