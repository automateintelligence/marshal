#!/usr/bin/env bash
# Usage recorder, step 2 of 3: the courier. Turns the sensor's file into state/usage.md.
#
#   scripts/usage/usage-courier.sh
#
# Reads ~/.cache/claude/statusline.json (written by statusline-sensor.sh) with jq and rewrites
# state/usage.md: the latest reading of the weekly and 5-hour limits, in plain language. It makes
# no model call, no network call and no git call (usage-push.sh does the git part).
#
# Rules (docs/usage-recorder-spec.md):
#   - File older than 90 minutes (by its captured_at): both limits are written as "stale" with the
#     file's age. The old percent is never shown as if it were current.
#   - captured_at up to 5 minutes in the future is clock skew (age 0). More than 5 minutes in
#     the future: "stale", because the clock must have changed.
#   - A limit missing from the file, or with a resets_at already in the past: "absent".
#   - resets_at is shown in America/Los_Angeles; the UTC epoch seconds are kept as the truth.
#   - state/usage-log.md gets one new line only when the weekly percent moved 1 point or more
#     since the last logged line, or the weekly or 5-hour reading became or stopped being
#     stale or absent. Hourly runs that see nothing new add nothing to the log.
#
# Install: this script is run by usage-push.sh, which is the one hourly cron job (see its header).
# Test settings (not needed in normal use): USAGE_STATUSLINE_FILE (the sensor's file),
# USAGE_STATE_DIR (where usage.md and usage-log.md go), USAGE_NOW (for example
# 2026-10-27T20:00:00Z) replaces the clock.
# Needs: jq, GNU date.
set -euo pipefail
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
file="${USAGE_STATUSLINE_FILE:-$HOME/.cache/claude/statusline.json}"
state_dir="${USAGE_STATE_DIR:-$repo/state}"
now_iso="${USAGE_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
stale_after=5400 # 90 minutes, in seconds
skew_allowed=300 # a capture time up to 5 minutes in the future is clock skew, counted as age 0

command -v jq >/dev/null || { echo "jq is not installed: sudo apt-get install -y jq" >&2; exit 2; }
now="$(date -u -d "$now_iso" +%s)"

plural() { if [ "$1" -eq 1 ]; then echo "$1 $2"; else echo "$1 ${2}s"; fi; }

# Seconds to words: "20 minutes", "3 hours 25 minutes", "2 days 4 hours".
age_text() {
  local m=$(($1 / 60))
  if [ "$m" -lt 120 ]; then
    plural "$m" minute
  elif [ "$m" -lt 2880 ]; then
    echo "$(plural $((m / 60)) hour) $(plural $((m % 60)) minute)"
  else
    echo "$(plural $((m / 1440)) day) $(plural $((m % 1440 / 60)) hour)"
  fi
}

pacific() { TZ=America/Los_Angeles date -d "@$1" '+%a %Y-%m-%d %H:%M %Z'; }
pacific_short() { TZ=America/Los_Angeles date -d "@$1" '+%Y-%m-%d %H:%M %Z'; }

# Five values, one per line, empty when missing or not the right type, then an "end" line (so
# trailing empty values survive the shell stripping trailing newlines):
# captured_at, weekly percent, weekly resets_at, 5-hour percent, 5-hour resets_at.
read -r -d '' jq_fields <<'EOF' || true
def pick(f): try f catch null;
def pct(w): pick(.rate_limits[w].used_percentage) | if type == "number" then tostring else "" end;
def rst(w): pick(.rate_limits[w].resets_at) | if type == "number" then floor | tostring else "" end;
[ (pick(.captured_at) | if type == "string" then . else "" end),
  pct("seven_day"), rst("seven_day"), pct("five_hour"), rst("five_hour"), "end" ] | .[]
EOF

fields=()
if [ -f "$file" ] && out="$(jq -r "$jq_fields" "$file" 2>/dev/null)"; then
  mapfile -t fields <<<"$out"
fi

# File level: fresh, or stale with the reason in plain words.
file_state=fresh
source_line=""
note=""
wk_pct=""; wk_reset=""; fh_pct=""; fh_reset=""
if [ ! -f "$file" ]; then
  file_state=stale
  source_line="no statusline file found at $file. STALE."
  note="There is no statusline file, so there is no reading."
elif [ "${#fields[@]}" -ne 6 ]; then
  file_state=stale
  source_line="the statusline file at $file could not be read as JSON. STALE."
  note="The statusline file could not be read, so there is no reading."
else
  captured="${fields[0]}"
  wk_pct="${fields[1]}"; wk_reset="${fields[2]}"; fh_pct="${fields[3]}"; fh_reset="${fields[4]}"
  if [[ "$captured" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
    && captured_epoch="$(date -u -d "$captured" +%s 2>/dev/null)"; then
    age=$((now - captured_epoch))
    if [ "$age" -lt "-$skew_allowed" ]; then
      file_state=stale
      source_line="statusline file captured $captured, $(age_text $((-age))) in the future. STALE: capture time is in the future, clock changed?"
      note="The statusline file says it was captured $(age_text $((-age))) in the future (more than 5 minutes ahead of this clock), so the clock may have changed and its reading is not shown as current."
    elif [ "$age" -gt "$stale_after" ]; then
      file_state=stale
      source_line="statusline file captured $captured, $(age_text "$age") old. STALE: older than 90 minutes."
      note="The statusline file is $(age_text "$age") old (the limit is 90 minutes), so its last reading is not shown as current."
    else
      if [ "$age" -lt 0 ]; then age=0; fi
      source_line="statusline file captured $captured, $(age_text "$age") old (counts as stale after 90 minutes)."
    fi
  else
    file_state=stale
    source_line="the statusline file has no valid captured_at time, so its age is unknown. STALE."
    note="The statusline file has no valid capture time, so its age is unknown and its reading is not shown."
  fi
fi

# Limit level: ok, absent-missing, absent-past, or stale.
window_status() {
  if [ "$file_state" = stale ]; then echo stale
  elif [ -z "$1" ] || [ -z "$2" ]; then echo absent-missing
  elif [ "$2" -le "$now" ]; then echo absent-past
  else echo ok
  fi
}
wk_status="$(window_status "$wk_pct" "$wk_reset")"
fh_status="$(window_status "$fh_pct" "$fh_reset")"

section() { # title percent resets_at status
  printf '## %s\n\n' "$1"
  case "$4" in
    ok)
      printf 'State: ok\nUsed: %s%%\nResets: %s\nresets_at (UTC epoch seconds, the truth): %s\n' \
        "$2" "$(pacific "$3")" "$3" ;;
    absent-missing)
      printf 'State: absent\nThe statusline did not report this limit. Do not use a number for it from this file.\n' ;;
    absent-past)
      printf 'State: absent\nThe statusline gave a reset time that is already in the past (%s, epoch %s), so its number is out of date. Do not use it.\n' \
        "$(pacific_short "$3")" "$3" ;;
    stale)
      printf 'State: stale\n%s\n' "$note" ;;
  esac
  echo
}

mkdir -p "$state_dir"
usage="$state_dir/usage.md"
tmp="$(mktemp "$state_dir/.usage.md.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
{
  echo "# Usage"
  echo
  echo "Latest reading of the owner's Claude usage limits, rewritten on every run of \`scripts/usage/usage-courier.sh\`. Do not edit by hand. Use a number only when its State is ok. History is in \`state/usage-log.md\`."
  echo
  echo "Written: $now_iso ($(pacific_short "$now"))"
  echo "Source: $source_line"
  echo
  section "Weekly limit (all models)" "$wk_pct" "$wk_reset" "$wk_status"
  section "Five-hour limit" "$fh_pct" "$fh_reset" "$fh_status"
} >"$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$usage"

# Log: compare this reading with the last logged line.
log="$state_dir/usage-log.md"

field() { # status percent -> the word or number written in the log
  case "$1" in
    ok) echo "$2%" ;;
    stale) echo stale ;;
    *) echo absent ;;
  esac
}
kind() { case "$1" in stale | absent) echo "$1" ;; *%) echo percent ;; *) echo none ;; esac; }

wk_field="$(field "$wk_status" "$wk_pct")"
fh_field="$(field "$fh_status" "$fh_pct")"

prev=""
if [ -f "$log" ]; then
  prev="$(grep -E '^- [0-9]{4}-' "$log" | tail -n 1 || true)"
fi
prev_wk="$(printf '%s\n' "$prev" | awk -F' [|] ' '{ sub(/^week /, "", $2); print $2 }')"
prev_fh="$(printf '%s\n' "$prev" | awk -F' [|] ' '{ sub(/^5-hour /, "", $3); print $3 }')"

should_log() {
  [ -n "$prev" ] || return 0
  [ "$(kind "$wk_field")" = "$(kind "$prev_wk")" ] || return 0
  [ "$(kind "$fh_field")" = "$(kind "$prev_fh")" ] || return 0
  if [ "$(kind "$wk_field")" = percent ]; then
    awk -v a="${wk_field%\%}" -v b="${prev_wk%\%}" \
      'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d >= 1 - 1e-9) }' && return 0
  fi
  return 1
}

if should_log; then
  if [ ! -f "$log" ]; then
    cat >"$log" <<'EOF'
# Usage log

One line each time the weekly percent has moved 1 point or more since the last line, or the weekly or 5-hour reading became or stopped being stale or absent. Written by `scripts/usage/usage-courier.sh`. Times are UTC with Pacific time in brackets.
"week" is the weekly limit for all models. "5-hour" is the rolling 5-hour limit.
"stale" means the statusline file was more than 90 minutes old, so there was no current reading.
"absent" means the statusline did not report that limit, or its reset time had already passed.

EOF
  fi
  printf -- '- %s (%s) | week %s | 5-hour %s\n' "$now_iso" "$(pacific_short "$now")" "$wk_field" "$fh_field" >>"$log"
fi
