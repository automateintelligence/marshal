#!/bin/sh
# Tests for the plugin's SessionStart hook (scripts/session-start-worker-rules.sh) and its wiring
# (hooks/hooks.json, .claude-plugin/plugin.json). Runs against a throwaway HOME.
# Needs python3 to parse the JSON. Usage: sh test_session_start_hook.sh   (exit 0 = all pass)

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root="$here/.."
hook="$here/session-start-worker-rules.sh"
rules="$root/docs/worker-rules.md"
BEGIN='<!-- marshal:worker-rules:begin -->'
END='<!-- marshal:worker-rules:end -->'
HEADER='Marshal worker rules (from the Marshal plugin). Follow them in this session.'

work=$(mktemp -d "${TMPDIR:-/tmp}/ss-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
HOME="$work/home"; export HOME
mkdir -p "$HOME/.claude"
unset CLAUDE_CONFIG_DIR CLAUDE_MD

fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

# json_field FILE: read the hook's stdout (a file) as JSON; print hookEventName, a tab, then the
# additionalContext text exactly as decoded. Exit 1 when it is not the expected JSON.
json_field() {
    python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
o = d["hookSpecificOutput"]
sys.stdout.write(o["hookEventName"] + "\t" + o["additionalContext"])
' "$1"
}
# decoded_equals FILE EXPECTED-FILE: the decoded context equals the file exactly.
decoded_equals() {
    json_field "$1" > "$work/decoded" 2> /dev/null || return 1
    { printf 'SessionStart\t'; cat "$2"; } | cmp -s - "$work/decoded"
}

expected="$work/expected.txt"
{ printf '%s\n\n' "$HEADER"; cat "$rules"; } > "$expected"

# 1. No user CLAUDE.md: the rules are injected as valid JSON.
sh "$hook" < /dev/null > "$work/out" 2> "$work/err"; rc=$?
check "no CLAUDE.md: exits 0" '[ "$rc" -eq 0 ]'
check "no CLAUDE.md: output is valid JSON for SessionStart" 'json_field "$work/out" > /dev/null'
check "no CLAUDE.md: injected text is the header plus docs/worker-rules.md, byte for byte" 'decoded_equals "$work/out" "$expected"'
check "no CLAUDE.md: nothing on stderr" '[ ! -s "$work/err" ]'
check "output is one line" '[ "$(wc -l < "$work/out")" -eq 1 ]'

# 2. A CLAUDE.md without the marker block: still injected.
printf '# My own rules\n- be brief\n' > "$HOME/.claude/CLAUDE.md"
sh "$hook" < /dev/null > "$work/out"
check "CLAUDE.md without marker: injected" 'decoded_equals "$work/out" "$expected"'

# 3. A CLAUDE.md with the marker block: nothing is injected.
{ printf '# My own rules\n\n%s\n' "$BEGIN"; cat "$rules"; printf '%s\n' "$END"; } > "$HOME/.claude/CLAUDE.md"
sh "$hook" < /dev/null > "$work/out"; rc=$?
check "CLAUDE.md with marker block: exits 0" '[ "$rc" -eq 0 ]'
check "CLAUDE.md with marker block: stdout is empty" '[ ! -s "$work/out" ]'

# 3b. The real installer's output counts as the marker block.
rm -f "$HOME/.claude/CLAUDE.md"
sh "$here/install-worker-rules.sh" --apply > /dev/null 2>&1
sh "$hook" < /dev/null > "$work/out"
check "after install-worker-rules.sh --apply: stdout is empty" '[ ! -s "$work/out" ]'

# 3c. Only the begin marker is needed (damaged block): still nothing, no duplicates.
printf 'x\n%s\n' "$BEGIN" > "$HOME/.claude/CLAUDE.md"
sh "$hook" < /dev/null > "$work/out"
check "begin marker alone: stdout is empty" '[ ! -s "$work/out" ]'

# 4. CLAUDE_CONFIG_DIR moves the user's CLAUDE.md.
mkdir -p "$work/cfg"
printf '%s\n' "$BEGIN" > "$work/cfg/CLAUDE.md"
rm -f "$HOME/.claude/CLAUDE.md"
CLAUDE_CONFIG_DIR="$work/cfg" sh "$hook" < /dev/null > "$work/out"
check "CLAUDE_CONFIG_DIR with marker: stdout is empty" '[ ! -s "$work/out" ]'
printf '%s\n' "$BEGIN" > "$HOME/.claude/CLAUDE.md"
printf '# no marker here\n' > "$work/cfg/CLAUDE.md"
CLAUDE_CONFIG_DIR="$work/cfg" sh "$hook" < /dev/null > "$work/out"
check "CLAUDE_CONFIG_DIR without marker ignores the marker in HOME/.claude" 'decoded_equals "$work/out" "$expected"'
rm -f "$HOME/.claude/CLAUDE.md"

# 5. The event JSON Claude Code sends on stdin is accepted.
printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"/tmp"}' | sh "$hook" > "$work/out"; rc=$?
check "event JSON on stdin: injected" '[ "$rc" -eq 0 ] && decoded_equals "$work/out" "$expected"'

# 6. Escaping: quotes, backslashes, tabs, carriage returns, non-ASCII text and control characters.
fake="$work/plugin"
mkdir -p "$fake/scripts" "$fake/docs"
cp "$hook" "$fake/scripts/"
printf 'say "hi"\nC:\\path\\new\tTabbed\r\nunicode: caf\303\251 \342\200\224 done\nbell:\007 end\n' > "$fake/docs/worker-rules.md"
sh "$fake/scripts/session-start-worker-rules.sh" < /dev/null > "$work/out"
check "special characters: valid JSON" 'json_field "$work/out" > /dev/null'
printf 'say "hi"\nC:\\path\\new\tTabbed\r\nunicode: caf\303\251 \342\200\224 done\nbell: end\n' > "$work/special.expected"
{ printf '%s\n\n' "$HEADER"; cat "$work/special.expected"; } > "$work/special.full"
check "special characters: decoded text is exact (control characters dropped)" 'decoded_equals "$work/out" "$work/special.full"'

# 7. Missing or empty rules file: nothing, exit 0.
rm -f "$fake/docs/worker-rules.md"
sh "$fake/scripts/session-start-worker-rules.sh" < /dev/null > "$work/out"; rc=$?
check "missing rules file: exit 0, no output" '[ "$rc" -eq 0 ] && [ ! -s "$work/out" ]'
: > "$fake/docs/worker-rules.md"
sh "$fake/scripts/session-start-worker-rules.sh" < /dev/null > "$work/out"; rc=$?
check "empty rules file: exit 0, no output" '[ "$rc" -eq 0 ] && [ ! -s "$work/out" ]'

# 8. hooks.json is valid, registers this script for SessionStart, and the command runs.
check "hooks.json is valid JSON" 'python3 -I -c "import json,sys; json.load(open(sys.argv[1]))" "$root/hooks/hooks.json"'
cmd=$(python3 -I -c '
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]
print(h["hooks"][0]["command"])
' "$root/hooks/hooks.json")
check "hooks.json command points at scripts/session-start-worker-rules.sh" 'printf %s "$cmd" | grep -q "\${CLAUDE_PLUGIN_ROOT}/scripts/session-start-worker-rules.sh"'
CLAUDE_PLUGIN_ROOT="$root" sh -c "$cmd" < /dev/null > "$work/out"; rc=$?
check "hooks.json command runs with CLAUDE_PLUGIN_ROOT set" '[ "$rc" -eq 0 ] && decoded_equals "$work/out" "$expected"'

# 9. plugin.json basics.
check "plugin.json: name marshal, version 0.1.0, license MIT" 'python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1]))
sys.exit(0 if (d[\"name\"],d[\"version\"],d[\"license\"])==(\"marshal\",\"0.1.0\",\"MIT\") else 1)
" "$root/.claude-plugin/plugin.json"'
check "plugin.json skills path exists and holds the four skills" '[ -f "$root/.claude/skills/handoff/SKILL.md" ] && [ -f "$root/.claude/skills/grilling/SKILL.md" ] && [ -f "$root/.claude/skills/grill-with-docs/SKILL.md" ] && [ -f "$root/.claude/skills/domain-modeling/SKILL.md" ] && [ -f "$root/.claude/skills/LICENSE-mattpocock-skills.txt" ]'

echo
if [ "$fails" -eq 0 ]; then echo "all tests passed"; else echo "$fails test(s) failed"; exit 1; fi
