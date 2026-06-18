# lib/ws-doctor-checks.sh — the individual ws-doctor checks.
#
# Sourced by bin/ws-doctor after it defines the PASS/WARN/FAIL/SKIP
# recorders. Each check_* function is independent, appends one report
# line via those recorders, and never exits — so one run reports every
# problem at once. The dispatcher (CHECKS array) and the rendering live
# in bin/ws-doctor; this file is just the check bodies, split out to keep
# the entry point readable. The catalogue of failure modes these guard
# against is documented in bin/ws-doctor's header.
#
# These functions assume the caller has already sourced lib/common.sh
# (for `warn`) and exported DOTFILES_DIR.

# ─── 1. aerospace config freshness ──────────────────────────────────────────
# Compare aerospace.toml's mtime against the running aerospace daemon's
# start time. If the toml is newer, the daemon is serving stale bindings —
# `aerospace reload-config` is the fix (or quit + relaunch AeroSpace.app).
check_aerospace_freshness() {
  local toml="$HOME/.config/aerospace/aerospace.toml"
  [[ -r "$toml" ]] || { SKIP aerospace-freshness "$toml missing"; return; }

  local pid
  pid=$(pgrep -x AeroSpace | head -1)
  if [[ -z "$pid" ]]; then
    FAIL aerospace-freshness "AeroSpace.app not running — launch from /Applications or 'open -a AeroSpace'"
    return
  fi

  local toml_mtime aero_start_str aero_start_epoch
  aero_start_str=$(ps -o lstart= -p "$pid" | xargs)
  aero_start_epoch=$(date -j -f '%a %b %d %T %Y' "$aero_start_str" +%s 2>/dev/null) || {
    WARN aerospace-freshness "couldn't parse AeroSpace start time ($aero_start_str)"
    return
  }
  toml_mtime=$(stat -f %m "$toml")

  if (( toml_mtime > aero_start_epoch )); then
    local age=$(( toml_mtime - aero_start_epoch ))
    # `aerospace reload-config` is in-process — it doesn't restart the
    # daemon, so a successful reload leaves ps lstart unchanged. We
    # can't distinguish "toml edited and reloaded" from "toml edited and
    # never reloaded". WARN is honest; reload is idempotent + cheap.
    WARN aerospace-freshness "aerospace.toml is $(_humanize_age $age) newer than running AeroSpace.app — if chords feel stale, run: aerospace reload-config"
  else
    PASS aerospace-freshness "AeroSpace up since $(date -r "$aero_start_epoch" '+%Y-%m-%d %H:%M'); toml untouched since"
  fi
}

_humanize_age() {
  local s="$1"
  if   (( s > 86400 )); then printf '%dd' $(( s / 86400 ))
  elif (( s > 3600  )); then printf '%dh' $(( s / 3600 ))
  elif (( s > 60    )); then printf '%dm' $(( s / 60 ))
  else                       printf '%ds' "$s"
  fi
}

# ─── 2. keystroke collision ─────────────────────────────────────────────────
# Find every osascript `keystroke X using <modifiers>` invocation in the
# repo + deployed launchers. For each, compute: if Caps/Hyper is still held,
# the event becomes Hyper+X. If Hyper+X is a real aerospace.toml binding,
# flag it.
#
# Hyper-bound keys are read live from aerospace.toml's [mode.main.binding]
# section — adding a binding automatically tightens the lint.
check_keystroke_collision() {
  local toml="$HOME/.config/aerospace/aerospace.toml"
  [[ -r "$toml" ]] || { SKIP keystroke-collision "$toml missing"; return; }

  # Extract keys bound under the full Hyper layer (cmd-alt-ctrl-shift-X).
  # AeroSpace's binding syntax: `cmd-alt-ctrl-shift-h = '…'`. Strip
  # comments, lowercase, dedup. Named keys (tab, escape, return,
  # semicolon, comma) keep their raw aerospace name; we map the common
  # ones back to their literal characters below.
  local hyper_keys
  hyper_keys=$(awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*cmd-alt-ctrl-shift-[A-Za-z0-9_]+[[:space:]]*=/ {
      match($0, /cmd-alt-ctrl-shift-[A-Za-z0-9_]+/)
      k = substr($0, RSTART, RLENGTH)
      sub(/^cmd-alt-ctrl-shift-/, "", k)
      print tolower(k)
    }
  ' "$toml" | sort -u)

  # AeroSpace key-name → literal character. osascript `keystroke ";"`
  # would collide with Hyper+semicolon; same for comma. Keep small.
  declare -A name_to_char=( [semicolon]=";" [comma]="," [period]="." )

  local key resolved=""
  for key in $hyper_keys; do
    if [[ -n "${name_to_char[$key]:-}" ]]; then
      resolved+="${name_to_char[$key]} "
    else
      resolved+="$key "
    fi
  done

  # Scan scope: the live keymap surface — aerospace.toml (launchers live
  # here as `open -a` / osascript now) plus the dotfiles bin/ helpers.
  # Orphaned sigil binaries under ~/.local/bin/ws-* are no longer wired to
  # any chord, so scanning them would flag collisions in dead code.
  local scope=(
    "$DOTFILES_DIR/bin/"*
    "$toml"
  )

  local hits=0 first_msg=""
  local file line content lit
  # Grep for: osascript ... keystroke "X" using ...
  # The literal could be a single character ("n") or named ("tab").
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    file="${match%%:*}"
    line="${match#*:}"; line="${line%%:*}"
    content="${match#*:*:}"

    # Extract the literal inside `keystroke "X"` or `keystroke "X" using ...`.
    # Skip menu-click and other patterns that contain "keystroke" only in
    # comments — only react to a real call site.
    lit=$(printf '%s\n' "$content" | sed -nE 's/.*keystroke[[:space:]]+"([^"]+)".*/\1/p')
    [[ -z "$lit" ]] && continue
    lit=$(printf '%s' "$lit" | tr '[:upper:]' '[:lower:]')

    # Only single-character literals can be hit by simple Hyper contamination;
    # named keys (return, tab, etc.) are different code paths. Keep the
    # multi-char branch open in case we ever bind hyper - return.
    local is_collision=
    if printf '%s\n' $resolved | grep -Fxq -- "$lit"; then
      is_collision=1
    fi

    if [[ -n "$is_collision" ]]; then
      hits=$((hits + 1))
      local rel="${file/#$HOME/~}"
      [[ -z "$first_msg" ]] && first_msg="$rel:$line: keystroke \"$lit\" collides with Hyper+$lit"
      [[ -n "${VERBOSE:-}" ]] && warn "  $rel:$line: keystroke \"$lit\" → Hyper+$lit collision"
    fi
  done < <(grep -rHn -E 'osascript|keystroke' "${scope[@]}" 2>/dev/null \
           | grep -E 'keystroke[[:space:]]+"[^"]+"' \
           | grep -v -E '^\s*#|^[^:]+:[0-9]+:[[:space:]]*#')

  if (( hits == 0 )); then
    PASS keystroke-collision "no osascript keystrokes collide with Hyper layer"
  else
    FAIL keystroke-collision "$hits collision(s); first: $first_msg"
  fi
}

# ─── 3. source/deploy drift ─────────────────────────────────────────────────
# Configs in `~/dotfiles/configs/` are *copied* to runtime locations by
# bootstrap.sh. If a fix lands in only one of the two, the next bootstrap
# either reverts the fix (source stale) or the running system stays
# vulnerable (deploy stale).
#
# We don't reimplement the full source→dest mapping; we just compare every
# pair we know matters for keystroke safety.
check_source_deploy_drift() {
  # Pairs: source ↔ deployed. Anything keystroke-relevant goes here.
  # aerospace.toml is hand-written now (the sigil-generated fences are
  # gone), so bootstrap copies it verbatim and a byte-for-byte cmp is
  # meaningful — drift here means an edit landed in only one copy.
  # Hyperkey stores its config in user defaults, not a file we can
  # pair-cmp, so it's not represented here.
  local pairs=(
    "$DOTFILES_DIR/configs/aerospace.toml::$HOME/.config/aerospace/aerospace.toml"
    "$DOTFILES_DIR/configs/ghostty-config::$HOME/.config/ghostty/config"
  )

  local drifted=0 missing=0 detail=""
  local pair src dst
  for pair in "${pairs[@]}"; do
    src="${pair%%::*}"; dst="${pair#*::}"
    if [[ ! -f "$src" ]]; then
      missing=$((missing + 1))
      detail+="  missing source: ${src/#$HOME/~}\n"
      continue
    fi
    if [[ ! -f "$dst" ]]; then
      missing=$((missing + 1))
      detail+="  not deployed: ${dst/#$HOME/~}\n"
      continue
    fi
    if ! cmp -s "$src" "$dst"; then
      drifted=$((drifted + 1))
      detail+="  drift: ${src/#$HOME/~} vs ${dst/#$HOME/~}\n"
    fi
  done

  if (( drifted == 0 && missing == 0 )); then
    PASS source-deploy-drift "${#pairs[@]} keystroke configs in sync"
  elif (( drifted == 0 )); then
    WARN source-deploy-drift "$missing config(s) missing on one side"$'\n'"$detail"
  else
    FAIL source-deploy-drift "$drifted config(s) drifted; run: bash $DOTFILES_DIR/macos/bootstrap.sh"$'\n'"$detail"
  fi
}

# ─── 4. menu item resolution ────────────────────────────────────────────────
# Any launcher that uses `click menu item "X" of menu "Y" of menu bar 1`
# fails *silently* if upstream renames the menu item. We resolve each
# (app, menu, item) tuple against the live app via osascript. The app must
# be running for the AX query to work, so an unreachable app is reported
# as SKIP, not FAIL — the menu might be correct, we just can't tell.
check_menu_items() {
  # Scope: the live keymap surface — deployed aerospace.toml + dotfiles
  # bin/ helpers. Exclude ws-doctor itself — its own docs quote the
  # literal patterns we lint for, which the parser would otherwise pick
  # up as real refs.
  local files=(
    "$DOTFILES_DIR/bin/"*
    "$HOME/.config/aerospace/aerospace.toml"
  )

  # Parse: `click menu item "ITEM" of menu "MENU" ...` and figure out
  # which app the surrounding `tell application "APP"` or
  # `tell process "APP"` refers to. We accept either form.
  local refs=() seen=()
  local file
  for file in "${files[@]}"; do
    [[ -r "$file" ]] || continue
    # Skip ws-doctor itself — its docs quote the lint patterns we look
    # for ("APP", "Foo", "X"), which would otherwise count as real refs.
    [[ "${file##*/}" == "ws-doctor" ]] && continue
    # awk: track the last `tell application "X"` or `tell process "X"`
    # we saw on the same osascript chain. Lines come in either as
    # `-e '…'` continuations or as one long string. Strip full-line
    # `#` comments before feeding awk — keeps docstring examples like
    # `# tell application "X" to click menu item "Y" of menu "Z"` out
    # of the real-ref set. Belt-and-braces with the placeholder filter
    # below: this catches any future doc-comment that happens to spell
    # out a complete tell+click on the same line.
    local extracted
    extracted=$(sed -E 's/^[[:space:]]*#.*$//' "$file" | awk '
      function unquote(s) {
        # Strip everything before the first quote, then everything from
        # the next quote onward. Non-greedy [^"]* keeps us safe against
        # lines with multiple quoted segments.
        sub(/^[^"]*"/, "", s)
        sub(/".*$/, "", s)
        return s
      }
      {
        # Walk every tell-application/process on the line; the last one
        # before the click determines the target app context.
        line = $0
        while (match(line, /tell[[:space:]]+(application|process)[[:space:]]+"[^"]+"/)) {
          last_app = unquote(substr(line, RSTART, RLENGTH))
          line = substr(line, RSTART + RLENGTH)
        }
        # Now scan the original line for click-menu-item references.
        if (match($0, /click[[:space:]]+menu[[:space:]]+item[[:space:]]+"[^"]+"[[:space:]]+of[[:space:]]+menu[[:space:]]+"[^"]+"/)) {
          frag = substr($0, RSTART, RLENGTH)
          # frag = `click menu item "ITEM" of menu "MENU"`
          item_part = frag
          sub(/^click[[:space:]]+menu[[:space:]]+item[[:space:]]+"/, "", item_part)
          sub(/"[[:space:]]+of[[:space:]]+menu.*$/, "", item_part)
          menu_part = frag
          sub(/^.*of[[:space:]]+menu[[:space:]]+"/, "", menu_part)
          sub(/".*$/, "", menu_part)
          printf "%s\t%s\t%s\n", last_app, menu_part, item_part
        }
      }
    ')
    while IFS=$'\t' read -r app menu item; do
      # Need a real (app, menu, item) tuple. Empty app means the menu
      # click had no surrounding tell-application context (probably a
      # doc snippet), and obvious placeholders like ITEM/MENU/APP get
      # skipped — they're not real references.
      [[ -z "$app" || -z "$menu" || -z "$item" ]] && continue
      [[ "$item" =~ ^(ITEM|MENU|APP|X|Y)$ ]] && continue
      [[ "$menu" =~ ^(MENU|ITEM|X|Y)$ ]] && continue
      local key="$app|$menu|$item"
      # Dedup
      local already=
      for s in "${seen[@]}"; do [[ "$s" == "$key" ]] && already=1 && break; done
      [[ -n "$already" ]] && continue
      seen+=("$key")
      refs+=("$file"$'\t'"$app"$'\t'"$menu"$'\t'"$item")
    done <<< "$extracted"
  done

  if (( ${#refs[@]} == 0 )); then
    PASS menu-items "no menu-click references found"
    return
  fi

  local ok_count=0 fail_count=0 skipped=0 detail=""
  local ref
  for ref in "${refs[@]}"; do
    IFS=$'\t' read -r file app menu item <<< "$ref"
    if ! pgrep -ixq "$app" 2>/dev/null && ! pgrep -ix "$(printf '%s' "$app" | tr '[:upper:]' '[:lower:]')" >/dev/null 2>&1; then
      skipped=$((skipped + 1))
      detail+="  skip ($app not running): $menu › $item\n"
      continue
    fi
    # Probe: list every menu-item name under (app, menu). If our item
    # is in the list, pass. Errors → fail.
    local names
    names=$(osascript 2>/dev/null \
      -e "tell application \"System Events\" to tell process \"$app\" to get name of every menu item of menu \"$menu\" of menu bar 1" \
      || true)
    if [[ -z "$names" ]]; then
      fail_count=$((fail_count + 1))
      detail+="  FAIL: $app menu \"$menu\" unreadable (Accessibility?)\n"
      continue
    fi
    # Names come back comma-separated. Match exactly.
    if printf '%s' "$names" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -Fxq -- "$item"; then
      ok_count=$((ok_count + 1))
    else
      fail_count=$((fail_count + 1))
      detail+="  FAIL: $app › $menu has no item \"$item\" (${file##*/})\n"
    fi
  done

  if (( fail_count > 0 )); then
    FAIL menu-items "$fail_count broken / $ok_count ok / $skipped not-running"$'\n'"$detail"
  elif (( skipped > 0 )); then
    # SKIP is genuinely unverified, not broken — but a doctor that goes
    # silent on un-probable references is a doctor that misses upstream
    # menu renames. Keep it as a warn; make the action obvious in the
    # message so the user knows the fix is "open the app and re-run".
    WARN menu-items "$ok_count ok, $skipped unverified (app not running — launch it and re-run to probe)"$'\n'"$detail"
  else
    PASS menu-items "$ok_count menu reference(s) resolve"
  fi
}

# ─── 5. app references ──────────────────────────────────────────────────────
# Every `tell application "X"` resolves to an app via Launch Services. If X
# isn't installed and isn't a stock system app, AppleScript prompts the user
# to locate it — the launcher then blocks on the dialog. Report any reference
# whose .app bundle is missing.
#
# Stock system apps (Finder, System Events, System Settings) live under
# /System and don't need a Launch Services check.
check_app_references() {
  local files=(
    "$DOTFILES_DIR/bin/"*
    "$HOME/.config/aerospace/aerospace.toml"
  )

  # Apps whose presence is guaranteed by the OS / never resolved via LS.
  local stock_regex='^(Finder|System Events|System Settings|System Preferences|Automator|Calculator|Calendar|Clock|Console|Contacts|Dictionary|FaceTime|Home|Image Capture|Launchpad|Mail|Maps|Messages|Mission Control|Music|News|Notes|Photo Booth|Photos|Podcasts|Preview|QuickTime Player|Reminders|Safari|Shortcuts|Siri|Stickies|Stocks|Terminal|TextEdit|Time Machine|TV|Voice Memos|Weather|App Store)$'

  local apps=()
  local file
  for file in "${files[@]}"; do
    [[ -r "$file" ]] || continue
    # Skip ws-doctor itself — its docs quote `tell application "Foo"` /
    # `tell application "X"` / `tell application "APP"` as placeholders
    # in the lint-pattern documentation. Without this skip those names
    # leak in as fake refs and Launch Services can't resolve them.
    [[ "${file##*/}" == "ws-doctor" ]] && continue
    # Pull every `tell application "X"` and `tell process "X"`. Strip
    # full-line `#` comments first (shell + TOML share this prefix) so
    # docstrings like `# tell application "X" to make new window` in a
    # launcher's header don't leak in as fake app refs.
    while IFS= read -r app; do
      [[ -z "$app" ]] && continue
      apps+=("$file"$'\t'"$app")
    done < <(sed -E 's/^[[:space:]]*#.*$//' "$file" \
             | grep -oE 'tell[[:space:]]+(application|process)[[:space:]]+"[^"]+"' \
             | sed -E 's/^tell[[:space:]]+(application|process)[[:space:]]+"([^"]+)"$/\2/')
  done

  if (( ${#apps[@]} == 0 )); then
    PASS app-references "no `tell application` references found"
    return
  fi

  local seen=() missing=0 ok_count=0 detail=""
  local entry app file
  for entry in "${apps[@]}"; do
    IFS=$'\t' read -r file app <<< "$entry"
    local key="$app"
    local already=
    for s in "${seen[@]}"; do [[ "$s" == "$key" ]] && already=1 && break; done
    [[ -n "$already" ]] && continue
    seen+=("$key")

    if printf '%s' "$app" | grep -Eq "$stock_regex"; then
      ok_count=$((ok_count + 1))
      continue
    fi
    if [[ -d "/Applications/$app.app" || -d "$HOME/Applications/$app.app" \
       || -d "/System/Applications/$app.app" || -d "/System/Library/CoreServices/$app.app" ]]; then
      ok_count=$((ok_count + 1))
    else
      # Only fail if the script unconditionally talks to it. Most launchers
      # try multiple candidates (Ghostty / iTerm / Alacritty / …) and pick
      # the first one installed. We treat all references as WARN — a
      # missing optional candidate isn't a bug.
      missing=$((missing + 1))
      detail+="  missing: $app (${file##*/})\n"
    fi
  done

  if (( missing == 0 )); then
    PASS app-references "$ok_count app reference(s) resolve"
  else
    WARN app-references "$missing app(s) referenced but not installed (may be optional fallbacks)"$'\n'"$detail"
  fi
}

# ─── 6. aerospace workspace-name casing ─────────────────────────────────────
# AeroSpace reports `app-name` for each window. Anything that filters on
# `.app == "Foo"` (or `."app-name" == "Foo"`) breaks silently if the
# live name doesn't match exactly — process names and Finder display
# names can diverge.
check_aerospace_app_casing() {
  command -v aerospace >/dev/null 2>&1 || { SKIP aerospace-app-casing "aerospace not installed"; return; }
  if ! aerospace list-windows --all --json >/dev/null 2>&1; then
    SKIP aerospace-app-casing "aerospace daemon not responding"
    return
  fi

  local live_names
  live_names=$(aerospace list-windows --all --json 2>/dev/null \
               | jq -r '.[]."app-name" // empty' 2>/dev/null \
               | sort -u)

  local files=(
    "$DOTFILES_DIR/bin/"*
  )

  local mismatches=0 detail=""
  local match name match_norm live_norm hit
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    name=$(sed -nE 's/.*(\.app|"app-name")[[:space:]]*==[[:space:]]*"([^"]+)".*/\2/p' <<<"$match")
    [[ -z "$name" ]] && continue
    if printf '%s\n' $live_names | grep -Fxq -- "$name"; then continue; fi
    match_norm=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
    hit=
    while IFS= read -r live; do
      live_norm=$(printf '%s' "$live" | tr '[:upper:]' '[:lower:]')
      [[ "$live_norm" == "$match_norm" ]] && hit="$live" && break
    done <<< "$live_names"
    if [[ -n "$hit" ]]; then
      mismatches=$((mismatches + 1))
      detail+="  casing: script uses \"$name\" but aerospace reports \"$hit\" — ${match%%:*}\n"
    fi
  done < <(grep -rHn -E '(\.app|"app-name")[[:space:]]*==[[:space:]]*"[^"]+"' "${files[@]}" 2>/dev/null \
           | grep -v -E '#.*(\.app|"app-name")[[:space:]]*==')

  if (( mismatches == 0 )); then
    PASS aerospace-app-casing "no script/aerospace app-name casing mismatches"
  else
    FAIL aerospace-app-casing "$mismatches mismatch(es)"$'\n'"$detail"
  fi
}

# ─── 7. aerospace daemon reachable ──────────────────────────────────────────
# Verifies the daemon is up and responding. AeroSpace.app's CLI talks to
# the running .app via a unix socket; "Can't connect to AeroSpace server"
# is the failure signature. Most common trigger: cask installed but .app
# never launched (or System Settings → Accessibility permission denied).
check_aerospace_daemon() {
  command -v aerospace >/dev/null 2>&1 || { SKIP aerospace-daemon "aerospace not installed"; return; }
  local out exit_code
  out=$(aerospace list-monitors --json 2>&1)
  exit_code=$?
  if (( exit_code == 0 )); then
    PASS aerospace-daemon "daemon responsive (list-monitors round-trip OK)"
    return
  fi
  if [[ "$out" == *"Can't connect to AeroSpace server"* ]]; then
    FAIL aerospace-daemon "AeroSpace.app not running — launch from /Applications, grant Accessibility (System Settings → Privacy & Security), or run: open -a AeroSpace"
  else
    WARN aerospace-daemon "aerospace list-monitors failed (non-daemon reason): ${out:-unknown error}"
  fi
}

# ─── 8. phantom tiles (aerospace tree vs AX-visible per workspace) ────────
# AeroSpace's workspace tree can disagree with the AX window tree: a
# window opens, gets dropped into a workspace by a chord, then closes
# (or its app crashes) without aerospace getting a destroy event.
# Aerospace keeps the tile slot reserved — every other window on the
# workspace gets a slightly smaller share of the screen, with no visible
# tile in the reserved space. Observable as "the grid leaves an empty
# column" without a config explanation.
#
# Detection: for each app aerospace tracks on the focused workspace,
# compare aerospace's count of that app's windows against System Events'
# `count of windows of process`. AX count counts every window across
# every aerospace workspace (off-screen ones too — AeroSpace stashes
# non-focused-workspace windows at negative coords, not in a separate
# macOS Space), so aerospace's per-workspace count exceeding AX's
# whole-app count means aerospace is tracking windows that no longer
# exist in AX.
#
# Only runs against the focused workspace — that's the one the user can
# see and act on. Other workspaces could have phantoms too, but they're
# observable on switch and a manual `ws-doctor` re-run catches them.
check_phantom_tiles() {
  command -v aerospace >/dev/null 2>&1 \
    || { SKIP phantom-tiles "aerospace not installed"; return; }
  if ! aerospace list-monitors --json >/dev/null 2>&1; then
    SKIP phantom-tiles "aerospace daemon not responding"
    return
  fi

  local focused
  focused=$(aerospace list-workspaces --focused --json 2>/dev/null \
              | jq -r '.[0].workspace // empty')
  if [[ -z "$focused" ]]; then
    SKIP phantom-tiles "no focused workspace"
    return
  fi

  local aero_json
  aero_json=$(aerospace list-windows --workspace "$focused" --json 2>/dev/null)
  local aero_total
  aero_total=$(jq 'length' <<<"$aero_json" 2>/dev/null)
  if [[ -z "$aero_total" || "$aero_total" == "0" ]]; then
    PASS phantom-tiles "workspace '$focused' is empty"
    return
  fi

  # Group by app-name, compare per-app aerospace count vs AX count.
  local phantoms=0 detail=""
  while IFS=$'\t' read -r app aero_n; do
    [[ -z "$app" ]] && continue
    local ax_n
    ax_n=$(osascript -e "tell application \"System Events\"" \
                    -e "  if exists process \"$app\" then" \
                    -e "    return count of windows of process \"$app\"" \
                    -e "  end if" \
                    -e "  return 0" \
                    -e "end tell" 2>/dev/null)
    [[ -z "$ax_n" || ! "$ax_n" =~ ^[0-9]+$ ]] && ax_n=0
    if (( aero_n > ax_n )); then
      local diff=$(( aero_n - ax_n ))
      phantoms=$(( phantoms + diff ))
      detail+="    • $app: aerospace tracks $aero_n, AX-visible $ax_n (phantom: $diff)\n"
    fi
  done < <(jq -r 'group_by(.["app-name"]) | .[] | "\(.[0].["app-name"])\t\(length)"' \
             <<<"$aero_json" 2>/dev/null)

  if (( phantoms == 0 )); then
    PASS phantom-tiles "workspace '$focused': aerospace tree matches AX state ($aero_total window(s))"
  else
    local fix_msg="inspect:  aerospace list-windows --workspace $focused --json"$'\n'"  cleanup:  aerospace move-node-to-workspace --window-id <id> <other-ws>"$'\n'"            aerospace flatten-workspace-tree --workspace $focused"
    FAIL phantom-tiles "workspace '$focused' has $phantoms phantom tile(s) eating layout space:"$'\n'"$detail""  $fix_msg"
  fi
}
