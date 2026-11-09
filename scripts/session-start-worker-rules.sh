#!/bin/sh
# SessionStart hook of the Marshal plugin: hand the worker rules (docs/worker-rules.md) to every
# Claude Code session as additional context, so the rules apply without editing ~/.claude/CLAUDE.md.
#
# Prints one JSON object on stdout:
#   {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}
# Prints nothing (exit 0) when:
#   - the user's CLAUDE.md already carries the marker block written by install-worker-rules.sh
#     (the rules are already loaded; injecting them again would duplicate them), or
#   - the rules file is missing or empty.
# Never fails the session: always exits 0.
#
# The user's CLAUDE.md is $CLAUDE_CONFIG_DIR/CLAUDE.md when that variable is set, else ~/.claude/CLAUDE.md.
# Needs only sh, grep, sed, awk and cat.

BEGIN='<!-- marshal:worker-rules:begin -->'

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || exit 0
rules="$script_dir/../docs/worker-rules.md"
user_md="${CLAUDE_CONFIG_DIR:-${HOME:-/nonexistent}/.claude}/CLAUDE.md"

# Claude Code writes the event as JSON on stdin. Read it so the writer is not left with a closed pipe.
[ -t 0 ] || cat > /dev/null 2>&1

[ -s "$rules" ] || exit 0
if [ -f "$user_md" ] && grep -qF -- "$BEGIN" "$user_md" 2>/dev/null; then
    exit 0
fi

# JSON string escaping with sed: backslash, double quote, tab and carriage return become escape
# sequences; any other control character is dropped (the rules are plain text, none are expected).
# Then awk ends each line with a literal \n.
tab=$(printf '\t')
cr=$(printf '\r')
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"'
{
    printf 'Marshal worker rules (from the Marshal plugin). Follow them in this session.\n\n'
    cat "$rules"
} | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$tab/\\\\t/g" -e "s/$cr/\\\\r/g" -e 's/[[:cntrl:]]//g' \
  | awk '{ printf "%s\\n", $0 }'
printf '"}}\n'
exit 0
