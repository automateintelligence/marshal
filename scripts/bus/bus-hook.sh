#!/usr/bin/env bash
# Marshal bus hook, for Claude Code's SessionStart and UserPromptSubmit events. Installed at
# project level in this repo's .claude/settings.json; nothing in the owner's user settings.
#
# What it prints becomes part of the session's context, so it prints nothing at all unless
# there is news: new messages for this instance (framed as DATA, at most 5 in full), or one
# "bus:" line about a problem (at most once per 30 minutes, except a dropped message).
# It always exits 0 and never blocks a prompt or a start. Its work runs under a hard limit of
# 8 seconds (then 2 more before a kill); bus.py itself stops at 7. It checks the backend at most
# once a minute (poll.json in the state dir), and not at all before a rate limit's end.
# It does nothing when MARSHAL_BUS_DISABLED is set, when this machine has no bus name, or when
# state/bus.md has no current issue yet. Hook input on stdin is not read.

[ -n "${MARSHAL_BUS_DISABLED:-}" ] && exit 0
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
command -v timeout >/dev/null 2>&1 || exit 0

timeout -k 2 8 python3 -I "$here/bus.py" hook </dev/null 2>/dev/null || true
exit 0
