#!/bin/sh
# Tests for .github/workflows/guard-state.yml: runs the workflow's shell step against throwaway
# repos with the label present and absent. (The YAML itself runs only on GitHub.)
# Usage: sh test_guard_state_workflow.sh   (exit 0 = all pass)

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
wf="$here/../.github/workflows/guard-state.yml"

work=$(mktemp -d "${TMPDIR:-/tmp}/gs-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_GLOBAL
GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_SYSTEM
GIT_AUTHOR_NAME=t; GIT_AUTHOR_EMAIL=t@example.com; GIT_COMMITTER_NAME=t; GIT_COMMITTER_EMAIL=t@example.com
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

# The step's script: everything under "run: |", with the 10-space indent removed.
sed -n '/^        run: |$/,$p' "$wf" | sed '1d; s/^          //' > "$work/step.sh"
check "found the step script" '[ -s "$work/step.sh" ]'

check "runs only in the public repo" 'grep -q "if: github.repository == .automateintelligence/marshal." "$wf"'
check "the only third-party action is actions/checkout" '[ "$(grep -c "uses:" "$wf")" -eq 1 ] && grep -q "uses: actions/checkout@" "$wf"'
check "re-runs when the label is added or removed" 'grep -q "types: \[opened, synchronize, reopened, labeled, unlabeled\]" "$wf"'
check "failure message is the agreed text" 'grep -qF "This PR changes state/. Your Marshal state belongs in your own private repo, not here. See README: Install." "$wf"'

repo="$work/repo"
git init -q -b main "$repo"
mkdir -p "$repo/state" "$repo/docs"
printf 'a\n' > "$repo/state/sessions.md"
printf 'a\n' > "$repo/docs/naming.md"
( cd "$repo" && git add -A && git commit -q -m base )
base=$(git -C "$repo" rev-parse HEAD)

# run_step HEAD_SHA LABEL(true|false)
run_step() {
    ( cd "$repo" && BASE_SHA="$base" HEAD_SHA="$1" HAS_LABEL="$2" sh "$work/step.sh" ) > "$work/out" 2>&1
    rc=$?
}

printf 'b\n' > "$repo/docs/naming.md"
( cd "$repo" && git commit -q -am "docs only" )
run_step "$(git -C "$repo" rev-parse HEAD)" false
check "docs-only PR passes" '[ "$rc" -eq 0 ]'

printf 'b\n' > "$repo/state/sessions.md"
( cd "$repo" && git commit -q -am "state change" )
head_state=$(git -C "$repo" rev-parse HEAD)
run_step "$head_state" false
check "state/ change without the label fails" '[ "$rc" -eq 1 ]'
check "failure message names the problem and the file" 'grep -qF "This PR changes state/. Your Marshal state belongs in your own private repo, not here. See README: Install." "$work/out" && grep -q "state/sessions.md" "$work/out"'
run_step "$head_state" true
check "state/ change with the template-change label passes" '[ "$rc" -eq 0 ]'

echo
if [ "$fails" -eq 0 ]; then echo "all tests passed"; else echo "$fails test(s) failed"; exit 1; fi
