#!/usr/bin/env bash
# ssh-chip.sh — sketchybar item for outbound SSH presence.
#
# Detects active ssh client connections via `lsof` (ESTABLISHED TCP
# sockets owned by the `ssh` command), then resolves the user-facing
# host alias from each ssh process's command line (so `ssh ubuntu-web`
# shows as `ubuntu-web`, not its IP).
#
# Output states:
#   • 0 sessions → drawing=off (chip invisible)
#   • 1 session  → " <host>"
#   • 2+         → " <count> ssh"
#
# Click behavior:
#   • left click → trigger a re-scan + print sessions to stderr
#   • right click → write the list to /tmp/ws-ssh-active.txt for
#                   external tooling (raycast, alfred, terminal popup)
# More sophisticated popups can be wired later.
#
# Test hook: set WS_SSH_LSOF_OVERRIDE to a file path with mock lsof
# output to exercise the parsing logic without real connections.

set -u

# shellcheck source=/dev/null
source "$HOME/.config/sketchybar/colors.sh"

SSH_ACCENT="0xfff9e2af"     # catppuccin yellow — "in flight" feel
SSH_DIM="$INACTIVE_LABEL"

# Source of lsof output. Allows test injection.
if [[ -n "${WS_SSH_LSOF_OVERRIDE:-}" && -r "$WS_SSH_LSOF_OVERRIDE" ]]; then
  lsof_lines=$(cat "$WS_SSH_LSOF_OVERRIDE")
else
  lsof_lines=$(lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null || true)
fi

# Filter to outbound ssh (exact command name match — excludes sshd).
ssh_lines=$(printf '%s\n' "$lsof_lines" | awk '$1 == "ssh"')

# Extract the target host from an ssh command line. Walks argv left to
# right after `ssh`, skipping option flags (and their argument tokens
# for the OpenSSH options that take one); returns the first positional.
# Falls back to the lsof remote IP if argv parsing yields nothing.
_extract_ssh_host() {
  local cmd="$1"
  printf '%s' "$cmd" | python3 -c '
import sys, shlex
try:
    args = shlex.split(sys.stdin.read())
except ValueError:
    sys.exit(0)
# OpenSSH single-letter options that take an argument.
TAKES_ARG = set("BbcDEeFIiJLlmOoPpQRSWw")
# Locate argv[0] = "ssh" (could be /usr/bin/ssh too).
start = 0
for idx, a in enumerate(args):
    if a == "ssh" or a.endswith("/ssh"):
        start = idx + 1
        break
i = start
while i < len(args):
    a = args[i]
    if a == "--":
        if i + 1 < len(args):
            print(args[i+1])
        break
    if a.startswith("-") and len(a) == 2 and a[1] in TAKES_ARG:
        i += 2; continue
    if a.startswith("-"):
        i += 1; continue
    print(a)
    break
' 2>/dev/null
}

targets=()
if [[ -n "$ssh_lines" ]]; then
  pids=$(printf '%s\n' "$ssh_lines" | awk '{print $2}' | sort -u)
  for pid in $pids; do
    cmd=$(ps -p "$pid" -o args= 2>/dev/null)
    host=""
    if [[ -n "$cmd" ]]; then
      host=$(_extract_ssh_host "$cmd")
    fi
    if [[ -z "$host" ]]; then
      # Fallback to remote IP from the first lsof row for this pid.
      host=$(printf '%s\n' "$ssh_lines" | awk -v pid="$pid" '$2 == pid {print $9; exit}' \
        | awk -F'->' '{print $2}' | sed 's/:[0-9]*$//')
    fi
    [[ -z "$host" ]] && continue
    host="${host##*@}"    # strip user@
    targets+=("$host")
  done
fi

# Deduplicate (one ssh process per pid, but multiplexed sockets via
# ControlMaster surface as multiple lsof rows for one process — and
# nothing stops a user from having two ssh sessions to the same host).
if (( ${#targets[@]} > 0 )); then
  unique=$(printf '%s\n' "${targets[@]}" | sort -u)
else
  unique=""
fi
count=$(printf '%s\n' "$unique" | grep -c . || true)

# Persist for external consumers (right-click hook).
{
  printf '# %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\n' "$unique"
} > /tmp/ws-ssh-active.txt 2>/dev/null

# Click handling. SENDER is set by sketchybar to the event that fired
# the script; BUTTON is set for mouse_clicked events.
case "${SENDER:-}" in
  mouse.clicked)
    case "${BUTTON:-left}" in
      right)
        # Surface the host list in a notification.
        if (( count > 0 )); then
          osascript -e "display notification \"$unique\" with title \"Active SSH sessions ($count)\"" 2>/dev/null || true
        fi
        ;;
    esac
    ;;
esac

# Render.
# Render label:
#   • 0 sessions → drawing=off
#   • 1 session  → "<host>"
#   • ≤3 short   → "<a> · <b>"           when joined length ≤ 20 chars
#   • else       → "<count> ssh"
#
# The threshold matches typical short ssh-config aliases (vm, vps,
# ubuntu-web, bastion). Long names or many sessions fall back to the
# compact count form to keep the right aux area uncluttered.
JOIN_SEP=" · "
JOIN_MAX_CHARS=20

if (( count == 0 )); then
  # Baseline: dim icon, no label. Stays visible so you know the chip is
  # installed and where it lives; lights up + names appear when sessions
  # are active.
  sketchybar --set "$NAME" \
    drawing=on \
    icon.color="$SSH_DIM" \
    label="" \
    label.drawing=off >/dev/null 2>&1 || true
elif (( count == 1 )); then
  sketchybar --set "$NAME" \
    drawing=on \
    icon.color="$SSH_ACCENT" \
    label="$unique" \
    label.color="$SSH_DIM" \
    label.drawing=on >/dev/null 2>&1 || true
else
  joined=$(printf '%s' "$unique" | paste -sd '@' - | sed "s/@/$JOIN_SEP/g")
  if (( count <= 3 && ${#joined} <= JOIN_MAX_CHARS )); then
    label="$joined"
  else
    label="$count ssh"
  fi
  sketchybar --set "$NAME" \
    drawing=on \
    icon.color="$SSH_ACCENT" \
    label="$label" \
    label.color="$SSH_DIM" \
    label.drawing=on >/dev/null 2>&1 || true
fi
