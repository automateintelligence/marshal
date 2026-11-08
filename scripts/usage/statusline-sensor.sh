#!/usr/bin/env bash
# Usage recorder, step 1 of 3: the sensor. A Claude Code statusLine command.
#
# Claude Code runs it after each assistant message and sends one JSON object on stdin that
# includes the weekly and 5-hour limit readings (rate_limits.seven_day / five_hour). The sensor
# adds "captured_at" (UTC) and saves the object to ~/.cache/claude/statusline.json: written to a
# temp file in the same folder, then moved into place, so a reader never sees half a file.
# No model call, no network. It always exits 0 and prints nothing on stderr: a broken status
# line must never get in the way of a session. Bad or empty input is not saved over a good file.
#
#   statusline-sensor.sh [existing-statusline-script]
#
# If a statusLine is already configured (most setups have one), pass the file that holds that
# command as the one argument. The sensor saves the input first, then runs that file with bash, gives it the same
# stdin byte for byte, and prints its output, so the status line looks exactly as before. With
# no argument it prints an empty status line. The wrapped command gets 2 seconds
# (USAGE_STATUSLINE_TIMEOUT, in seconds, changes that); if it runs longer it is stopped, and
# whatever it printed before then is the status line. The saved file is written either way.
#
# Install (once, on each machine whose sessions should feed the recorder):
#   1. Keep the current command: save it to a file the sensor can run.
#        jq -r '.statusLine.command' ~/.claude/settings.json > ~/.claude/statusline-original.sh
#   2. In ~/.claude/settings.json replace the "statusLine" entry with:
#        "statusLine": {
#          "type": "command",
#          "command": "<CHECKOUT>/scripts/usage/statusline-sensor.sh <HOME>/.claude/statusline-original.sh"
#        }
#      Use absolute paths: <CHECKOUT> is where you cloned this repo, <HOME> is your home folder.
#      (With no existing statusLine, leave off the second path.) Restart sessions to pick it up.
#
# Test settings (not needed in normal use): USAGE_STATUSLINE_FILE moves the saved file,
# USAGE_NOW (for example 2026-10-27T20:00:00Z) replaces the clock.
set -uo pipefail
exec 2>/dev/null

main() {
  local wrapped="${1:-}"
  local file="${USAGE_STATUSLINE_FILE:-$HOME/.cache/claude/statusline.json}"
  local now="${USAGE_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  local limit="${USAGE_STATUSLINE_TIMEOUT:-2}"
  local input tmp
  # The trailing "x" keeps the input's trailing newlines, which $(...) would otherwise strip.
  input="$(cat; printf x)" || input="x"
  input="${input%x}"

  if command -v jq >/dev/null && mkdir -p "$(dirname "$file")"; then
    tmp="$file.tmp.$$"
    if printf '%s' "$input" \
        | jq -ec --arg t "$now" 'if type == "object" then . + {captured_at: $t} else error("not an object") end' \
          > "$tmp" \
      && [ -s "$tmp" ]; then
      mv -f "$tmp" "$file"
    else
      rm -f "$tmp"
    fi
  fi

  if [ -n "$wrapped" ] && [ -f "$wrapped" ]; then
    printf '%s' "$input" | timeout -k 1 "$limit" bash "$wrapped" || true
  else
    echo
  fi
}

main "$@" || true
exit 0
