# Bash completion for the `ws` workspace CLI (and the `workspace` compat alias).
#
# Sourced from bashrc when present.

_ws() {
  local cur prev sub
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  sub="${COMP_WORDS[1]:-}"

  local subcommands="status get count themes name color icon add remove swap reorder move rotate reverse layout theme edit reset doctor verify migrate refresh host help"

  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
    return 0
  fi

  local cfg="${WS_CONFIG:-$HOME/.config/workspace/spaces.json}"
  local themes_dir="${WS_THEMES_DIR:-$HOME/.config/workspace/themes}"
  local layouts_dir="${WS_LAYOUTS_DIR:-$HOME/.config/workspace/layouts}"

  __ws_slot_indices() {
    [[ -r "$cfg" ]] || return
    jq -r '.spaces | keys | map(tonumber) | sort | .[]' "$cfg" 2>/dev/null
  }
  __ws_slot_names() {
    [[ -r "$cfg" ]] || return
    jq -r '.spaces | to_entries | .[].value.name // empty' "$cfg" 2>/dev/null
  }
  __ws_themes() {
    [[ -d "$themes_dir" ]] || return
    ( cd "$themes_dir" && ls *.json 2>/dev/null | sed 's/\.json$//' )
  }
  __ws_layouts() {
    [[ -d "$layouts_dir" ]] || return
    ( cd "$layouts_dir" && ls *.json 2>/dev/null | sed 's/\.json$//' )
  }

  case "$sub" in
    get|name|color|icon|remove|rotate)
      if [[ $COMP_CWORD -eq 2 ]]; then
        local slots
        slots="$(__ws_slot_indices)
$(__ws_slot_names)"
        COMPREPLY=( $(compgen -W "$slots" -- "$cur") )
      fi
      ;;
    swap|move)
      if [[ $COMP_CWORD -eq 2 || $COMP_CWORD -eq 3 ]]; then
        local slots
        slots="$(__ws_slot_indices)
$(__ws_slot_names)"
        if [[ "$sub" == move && $COMP_CWORD -eq 3 ]]; then
          slots="$slots
before
after"
        fi
        COMPREPLY=( $(compgen -W "$slots" -- "$cur") )
      fi
      ;;
    theme)
      [[ $COMP_CWORD -eq 2 ]] && COMPREPLY=( $(compgen -W "$(__ws_themes)" -- "$cur") )
      ;;
    layout)
      if [[ $COMP_CWORD -eq 2 ]]; then
        COMPREPLY=( $(compgen -W "save load list delete" -- "$cur") )
      elif [[ $COMP_CWORD -eq 3 ]] && [[ "${COMP_WORDS[2]}" == "load" || "${COMP_WORDS[2]}" == "delete" ]]; then
        COMPREPLY=( $(compgen -W "$(__ws_layouts)" -- "$cur") )
      fi
      ;;
    host)
      [[ $COMP_CWORD -eq 2 ]] && COMPREPLY=( $(compgen -W "status init reset list" -- "$cur") )
      ;;
    refresh)
      [[ $COMP_CWORD -eq 2 ]] && COMPREPLY=( $(compgen -W "--full" -- "$cur") )
      ;;
    add)
      [[ $COMP_CWORD -eq 2 ]] && COMPREPLY=( $(compgen -W "--no-prompt -q" -- "$cur") )
      ;;
    migrate)
      [[ $COMP_CWORD -eq 2 ]] && COMPREPLY=( $(compgen -W "--apply" -- "$cur") )
      ;;
    icon)
      if [[ $COMP_CWORD -eq 2 ]]; then
        local slots
        slots="search
$(__ws_slot_indices)
$(__ws_slot_names)"
        COMPREPLY=( $(compgen -W "$slots" -- "$cur") )
      fi
      ;;
  esac
}

complete -F _ws ws
complete -F _ws workspace
