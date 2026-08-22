# lib/ws-doctor-checks.sh — the individual ws-doctor checks.
#
# Sourced by bin/ws-doctor after it defines the PASS/WARN/FAIL/SKIP
# recorders. Each check_* function is independent, appends one report
# line via those recorders, and never exits — so one run reports every
# problem at once. The dispatcher (CHECKS array) and the rendering live
# in bin/ws-doctor; this file is just the check bodies, split out to keep
# the entry point readable. The catalogue of failure modes these guard
# against is documented in bin/ws-doctor's header. (The aerospace-era
# checks — freshness, keystroke collision, app casing, daemon, phantom
# tiles — were retired with AeroSpace; git history has the bodies.)
#
# These functions assume the caller has already sourced lib/common.sh
# (for `warn`) and exported DOTFILES_DIR.

# ─── 1. source/deploy drift ─────────────────────────────────────────────────
# Configs in `~/dotfiles/configs/` are *copied* to runtime locations by
# bootstrap.sh. If a fix lands in only one of the two, the next bootstrap
# either reverts the fix (source stale) or the running system stays
# vulnerable (deploy stale).
#
# We don't reimplement the full source→dest mapping; we just compare every
# pair we know matters. Hyperkey stores its config in user defaults, not a
# file we can pair-cmp, so it's not represented here.
check_source_deploy_drift() {
  local pairs=(
    "$DOTFILES_DIR/configs/ghostty-config::$HOME/.config/ghostty/config"
    "$DOTFILES_DIR/configs/tmux.conf::$HOME/.tmux.conf"
  )

  local drifted=0 missing=0 detail=""
  local pair src dst
  for pair in "${pairs[@]}"; do
    src="${pair%%::*}"; dst="${pair#*::}"
    if [[ ! -f "$src" ]]; then
      missing=$((missing + 1))
      detail+="  missing source: ${src/#$HOME/~}"$'\n'
      continue
    fi
    if [[ ! -f "$dst" ]]; then
      missing=$((missing + 1))
      detail+="  not deployed: ${dst/#$HOME/~}"$'\n'
      continue
    fi
    if ! cmp -s "$src" "$dst"; then
      drifted=$((drifted + 1))
      detail+="  drift: ${src/#$HOME/~} vs ${dst/#$HOME/~}"$'\n'
    fi
  done

  if (( drifted == 0 && missing == 0 )); then
    PASS source-deploy-drift "${#pairs[@]} configs in sync"
  elif (( drifted == 0 )); then
    WARN source-deploy-drift "$missing config(s) missing on one side"$'\n'"$detail"
  else
    FAIL source-deploy-drift "$drifted config(s) drifted; run: bash $DOTFILES_DIR/macos/bootstrap.sh"$'\n'"$detail"
  fi
}

# ─── 2. menu item resolution ────────────────────────────────────────────────
# Any script that uses `click menu item "X" of menu "Y" of menu bar 1`
# fails *silently* if upstream renames the menu item. We resolve each
# (app, menu, item) tuple against the live app via osascript. The app must
# be running for the AX query to work, so an unreachable app is reported
# as SKIP, not FAIL — the menu might be correct, we just can't tell.
check_menu_items() {
  # Scope: the dotfiles bin/ helpers. Exclude ws-doctor itself — its own
  # docs quote the literal patterns we lint for, which the parser would
  # otherwise pick up as real refs.
  local files=(
    "$DOTFILES_DIR/bin/"*
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
        # last_app used to persist file-wide, so a click-menu-item line
        # far from its tell block (e.g. after the block closed but
        # before a new one opened) got attributed to a stale app. Clear
        # it on "end tell" so attribution stays scoped to the block it
        # was actually seen in.
        if ($0 ~ /end[[:space:]]+tell/) { last_app = "" }
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
    if ! pgrep -ixq "$app" 2>/dev/null; then
      skipped=$((skipped + 1))
      detail+="  skip ($app not running): $menu › $item"$'\n'
      continue
    fi
    # Probe: list every menu-item name under (app, menu). If our item
    # is in the list, pass. Errors → fail. Emit one item per line
    # (text item delimiters = linefeed before the list→text coercion)
    # instead of AppleScript's default comma-join — an item name that
    # itself contains a comma would otherwise splinter into two "items"
    # and false-FAIL.
    local names
    names=$(osascript 2>/dev/null \
      -e "tell application \"System Events\"" \
      -e "  tell process \"$app\"" \
      -e "    set AppleScript's text item delimiters to linefeed" \
      -e "    set itemNames to name of every menu item of menu \"$menu\" of menu bar 1" \
      -e "    return itemNames as text" \
      -e "  end tell" \
      -e "end tell" \
      || true)
    if [[ -z "$names" ]]; then
      fail_count=$((fail_count + 1))
      detail+="  FAIL: $app menu \"$menu\" unreadable (Accessibility?)"$'\n'
      continue
    fi
    if printf '%s\n' "$names" | grep -Fxq -- "$item"; then
      ok_count=$((ok_count + 1))
    else
      fail_count=$((fail_count + 1))
      detail+="  FAIL: $app › $menu has no item \"$item\" (${file##*/})"$'\n'
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

# ─── 3. app references ──────────────────────────────────────────────────────
# Every `tell application "X"` resolves to an app via Launch Services. If X
# isn't installed and isn't a stock system app, AppleScript prompts the user
# to locate it — the script then blocks on the dialog. Report any reference
# whose .app bundle is missing.
#
# Stock system apps (Finder, System Events, System Settings) live under
# /System and don't need a Launch Services check.
check_app_references() {
  local files=(
    "$DOTFILES_DIR/bin/"*
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
    # full-line `#` comments first so docstrings like
    # `# tell application "X" to make new window` in a script's header
    # don't leak in as fake app refs.
    while IFS= read -r app; do
      [[ -z "$app" ]] && continue
      apps+=("$file"$'\t'"$app")
    done < <(sed -E 's/^[[:space:]]*#.*$//' "$file" \
             | grep -oE 'tell[[:space:]]+(application|process)[[:space:]]+"[^"]+"' \
             | sed -E 's/^tell[[:space:]]+(application|process)[[:space:]]+"([^"]+)"$/\2/')
  done

  if (( ${#apps[@]} == 0 )); then
    # Backticks here must be escaped — unescaped, bash treats them as a
    # command substitution even inside double quotes, so the message
    # would silently swallow "tell application" and try to run it.
    PASS app-references "no \`tell application\` references found"
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
      # Only fail if the script unconditionally talks to it. Most scripts
      # try multiple candidates (Ghostty / iTerm / Alacritty / …) and pick
      # the first one installed. We treat all references as WARN — a
      # missing optional candidate isn't a bug.
      missing=$((missing + 1))
      detail+="  missing: $app (${file##*/})"$'\n'
    fi
  done

  if (( missing == 0 )); then
    PASS app-references "$ok_count app reference(s) resolve"
  else
    WARN app-references "$missing app(s) referenced but not installed (may be optional fallbacks)"$'\n'"$detail"
  fi
}
