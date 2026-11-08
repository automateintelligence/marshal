#!/bin/sh
# Tests for install-worker-rules.sh. Runs against a throwaway HOME.
# Usage: sh test_install_worker_rules.sh   (exit 0 = all pass)

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
script="$here/install-worker-rules.sh"
rules="$here/../docs/worker-rules.md"
BEGIN='<!-- marshal:worker-rules:begin -->'
END='<!-- marshal:worker-rules:end -->'

work=$(mktemp -d "${TMPDIR:-/tmp}/wr-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
HOME="$work/home"; export HOME
unset CLAUDE_MD
target="$HOME/.claude/CLAUDE.md"

fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
count_backups() { ls "$HOME/.claude"/CLAUDE.md.bak.* 2>/dev/null | wc -l | tr -d ' '; }
block_matches_rules() {
    # The text between the markers must equal docs/worker-rules.md exactly.
    awk -v b="$BEGIN" -v e="$END" '$0==e{p=0} p{print} $0==b{p=1}' "$target" | cmp -s - "$rules"
}

# 1. Dry run on a missing file writes nothing.
out=$(sh "$script" 2>&1); rc=$?
check "dry run exits 0" '[ "$rc" -eq 0 ]'
check "dry run says it is a dry run" 'printf %s "$out" | grep -q "Dry run"'
check "dry run creates no file" '[ ! -e "$target" ]'

# 2. First --apply creates the file with the block.
sh "$script" --apply > /dev/null 2>&1; rc=$?
check "first apply exits 0" '[ "$rc" -eq 0 ]'
check "first apply creates the file" '[ -f "$target" ]'
check "one begin marker" '[ "$(grep -cxF -- "$BEGIN" "$target")" -eq 1 ]'
check "one end marker" '[ "$(grep -cxF -- "$END" "$target")" -eq 1 ]'
check "block equals rules file" 'block_matches_rules'
check "no backup when the file did not exist" '[ "$(count_backups)" -eq 0 ]'
cp "$target" "$work/after-first.md"

# 3. Second --apply changes nothing and makes no backup.
out=$(sh "$script" --apply 2>&1); rc=$?
check "second apply exits 0" '[ "$rc" -eq 0 ]'
check "second apply reports no change" 'printf %s "$out" | grep -q "No change"'
check "second apply leaves file identical" 'cmp -s "$target" "$work/after-first.md"'
check "second apply makes no backup" '[ "$(count_backups)" -eq 0 ]'

# 4. An edited block is replaced; text outside the markers is untouched.
{
    printf '# My own rules\n- keep this line\n\n'
    printf '%s\n' "$BEGIN"
    printf 'STALE LINE ONE\nSTALE LINE TWO\n'
    printf '%s\n' "$END"
    printf '\n## After the block\n- keep this too\n'
} > "$target"
sh "$script" --apply > /dev/null 2>&1; rc=$?
check "apply on edited block exits 0" '[ "$rc" -eq 0 ]'
check "stale block content removed" '! grep -q "STALE LINE" "$target"'
check "block replaced with rules file" 'block_matches_rules'
check "text before the block kept" '[ "$(sed -n 1,2p "$target")" = "$(printf "# My own rules\n- keep this line")" ]'
check "text after the block kept" '[ "$(tail -n 2 "$target")" = "$(printf "## After the block\n- keep this too")" ]'
check "backup made on change" '[ "$(count_backups)" -eq 1 ]'
check "backup holds the old content" 'grep -q "STALE LINE ONE" "$HOME"/.claude/CLAUDE.md.bak.*'

# 5. A file without markers gets the block appended; its text is kept.
printf '# Existing file\n- line one\n- line two (no newline at end)' > "$target"
sh "$script" --apply > /dev/null 2>&1; rc=$?
check "append apply exits 0" '[ "$rc" -eq 0 ]'
check "existing text kept at top" '[ "$(sed -n 1,3p "$target")" = "$(printf "# Existing file\n- line one\n- line two (no newline at end)")" ]'
check "appended block equals rules file" 'block_matches_rules'
check "end marker is the last line" '[ "$(tail -n 1 "$target")" = "$END" ]'

# 6. Dry run on a changed file reports the diff and writes nothing.
sed -i 's/^- Take times from the clock.*/- EDITED/' "$target"
cp "$target" "$work/before-dry.md"
out=$(sh "$script" 2>&1); rc=$?
check "dry run on changed file exits 0" '[ "$rc" -eq 0 ]'
check "dry run prints a line count summary" 'printf %s "$out" | grep -q "^Change for .*: +[0-9]* -[0-9]* lines"'
check "dry run writes nothing" 'cmp -s "$target" "$work/before-dry.md"'

# 7. Damaged markers are refused.
printf '%s\n%s\nx\n' "$BEGIN" "$BEGIN" > "$target"
sh "$script" --apply > /dev/null 2>&1; rc=$?
check "duplicate begin marker exits 2" '[ "$rc" -eq 2 ]'

echo
if [ "$fails" -eq 0 ]; then echo "all tests passed"; else echo "$fails test(s) failed"; exit 1; fi
