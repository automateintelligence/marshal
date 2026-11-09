#!/bin/sh
# Tests for scripts/init-workspace.sh (what /marshal:init runs). Throwaway HOME and folders, no network.
# Usage: sh test_init_workspace.sh   (exit 0 = all pass)

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/.." && pwd)
init="$here/init-workspace.sh"

work=$(mktemp -d "${TMPDIR:-/tmp}/init-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
HOME="$work/home"; export HOME
mkdir -p "$HOME"
GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_GLOBAL
GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_SYSTEM
GIT_AUTHOR_NAME=t; GIT_AUTHOR_EMAIL=t@example.com; GIT_COMMITTER_NAME=t; GIT_COMMITTER_EMAIL=t@example.com
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

# 1. A new workspace, with ~ expanded.
sh "$init" '~/ws' > "$work/out" 2>&1; rc=$?
ws="$HOME/ws"
check "init exits 0" '[ "$rc" -eq 0 ]'
for f in CLAUDE.md GLOSSARY.md .gitignore docs/RESUME.md docs/decision-format.md docs/naming.md docs/worker-rules.md \
         state/sessions.md state/priorities.md state/checklist.md state/watch.md \
         scripts/git-hooks/pre-push scripts/git-hooks/state-templates.manifest scripts/install-git-hooks.sh scripts/install-worker-rules.sh; do
    check "copied $f" '[ -f "$ws/$f" ]'
done
check "state/ is byte-for-byte the shipped templates" 'diff -r "$root/state" "$ws/state" > /dev/null'
check "CLAUDE.md still has its {{placeholders}} for the owner to fill" 'grep -q "{{OWNER}}" "$ws/CLAUDE.md"'
for f in README.md ROADMAP.md LICENSE .claude-plugin hooks commands .github .claude scripts/usage scripts/bus docs/specs \
         scripts/init-workspace.sh scripts/test_git_guard.sh; do
    check "not copied: $f" '[ ! -e "$ws/$f" ]'
done

# 2. A fresh repository: no commits, no remote, nothing pointing at the public repo.
check "is a git repository" '[ -d "$ws/.git" ]'
check "no commits" '! git -C "$ws" rev-parse -q --verify HEAD > /dev/null'
check "no remote" '[ -z "$(git -C "$ws" remote)" ]'
check "git config does not mention the public repo" '! grep -qi "automateintelligence" "$ws/.git/config"'
check "branch is main" '[ "$(git -C "$ws" symbolic-ref --short HEAD)" = main ]'

# 3. The privacy guard is installed and works in the new workspace.
check "pre-push hook installed and executable" '[ -x "$ws/.git/hooks/pre-push" ] && cmp -s "$ws/.git/hooks/pre-push" "$ws/scripts/git-hooks/pre-push"'
mkdir -p "$ws/github.com/automateintelligence"
git init -q --bare "$ws/github.com/automateintelligence/marshal.git"
( cd "$ws" && git remote add public github.com/automateintelligence/marshal.git && git add CLAUDE.md state && git commit -q -m "workspace" && git push -q public main ) > "$work/out" 2>&1; rc=$?
check "a push to the public Marshal address from the new workspace is refused" '[ "$rc" -ne 0 ] && grep -q "PUSH REFUSED" "$work/out"'
rm -rf "$ws/github.com"
git -C "$ws" remote remove public

# 4. Running again never overwrites the owner's edits.
printf 'MY OWN EDIT\n' > "$ws/state/priorities.md"
sh "$init" "$ws" > "$work/out" 2>&1; rc=$?
check "second run exits 0" '[ "$rc" -eq 0 ]'
check "second run keeps the edited file" '[ "$(cat "$ws/state/priorities.md")" = "MY OWN EDIT" ]'
check "second run says it kept it" 'grep -q "kept   state/priorities.md" "$work/out"'
check "second run keeps the repository and its commit" 'git -C "$ws" rev-parse -q --verify HEAD > /dev/null'

# 5. Optional pieces only when asked.
sh "$init" "$work/ws-usage" --with-usage > "$work/out" 2>&1; rc=$?
check "--with-usage exits 0" '[ "$rc" -eq 0 ]'
check "--with-usage copies the recorder" '[ -f "$work/ws-usage/scripts/usage/statusline-sensor.sh" ] && [ -f "$work/ws-usage/scripts/usage/test_usage_recorder.py" ]'
check "--with-usage does not copy the bus" '[ ! -e "$work/ws-usage/scripts/bus" ]'
check "--with-usage copies no compiled Python" '[ -z "$(find "$work/ws-usage" -name "*.pyc" -o -name __pycache__)" ]'
sh "$init" "$work/ws-bus" --with-bus > "$work/out" 2>&1; rc=$?
check "--with-bus exits 0" '[ "$rc" -eq 0 ]'
check "--with-bus copies the bus, its design and its hook settings" '[ -f "$work/ws-bus/scripts/bus/bus.py" ] && [ -f "$work/ws-bus/docs/specs/2026-10-26-marshal-bus.md" ] && [ -f "$work/ws-bus/.claude/settings.json" ]'
check "--with-bus does not copy the recorder" '[ ! -e "$work/ws-bus/scripts/usage" ]'
sh "$init" "$work/ws-bus" --with-usage > "$work/out" 2>&1
check "adding a flag later keeps the earlier pieces and adds the new one" '[ -f "$work/ws-bus/scripts/bus/bus.py" ] && [ -f "$work/ws-bus/scripts/usage/statusline-sensor.sh" ]'

# 6. Refusals.
sh "$init" "$root/inside-the-plugin" > "$work/out" 2>&1; rc=$?
check "a folder inside the plugin is refused (exit 2)" '[ "$rc" -eq 2 ]'
rm -rf "$root/inside-the-plugin"
for url in https://github.com/automateintelligence/marshal.git git@github.com:automateintelligence/marshal.git; do
    rm -rf "$work/clone"
    git init -q -b main "$work/clone"
    git -C "$work/clone" remote add github "$url"
    sh "$init" "$work/clone" > "$work/out" 2>&1; rc=$?
    check "a repository whose remote is $url is refused (exit 2)" '[ "$rc" -eq 2 ] && grep -q "PUBLIC Marshal repo" "$work/out"'
    check "nothing was copied into it" '[ ! -e "$work/clone/CLAUDE.md" ]'
done
rm -rf "$work/own"
git init -q -b main "$work/own"
git -C "$work/own" remote add github https://github.com/jane/my-marshal.git
sh "$init" "$work/own" > "$work/out" 2>&1; rc=$?
check "a repository with a private remote of the owner's is accepted" '[ "$rc" -eq 0 ] && [ -f "$work/own/CLAUDE.md" ]'
check "its remote is untouched" '[ "$(git -C "$work/own" remote get-url github)" = "https://github.com/jane/my-marshal.git" ]'
sh "$init" > "$work/out" 2>&1; rc=$?
check "no folder: usage error (exit 1)" '[ "$rc" -eq 1 ]'
sh "$init" "$work/x" --nope > "$work/out" 2>&1; rc=$?
check "unknown flag: usage error (exit 1)" '[ "$rc" -eq 1 ] && [ ! -e "$work/x" ]'

# 7. A different pre-push hook already there: files are copied, the guard is not, exit 3.
rm -rf "$work/hooked"
git init -q -b main "$work/hooked"
mkdir -p "$work/hooked/.git/hooks"
printf '#!/bin/sh\necho mine\n' > "$work/hooked/.git/hooks/pre-push"
sh "$init" "$work/hooked" > "$work/out" 2>&1; rc=$?
check "foreign pre-push hook: exit 3 with a clear message" '[ "$rc" -eq 3 ] && grep -q "NOT installed" "$work/out"'
check "foreign pre-push hook is left alone" 'grep -q "echo mine" "$work/hooked/.git/hooks/pre-push"'

# 8. Existing folder with the owner's other files, and a folder name with spaces.
mkdir -p "$work/with space"
printf 'keep me\n' > "$work/with space/notes.txt"
sh "$init" "$work/with space" > "$work/out" 2>&1; rc=$?
check "folder with a space in its name works" '[ "$rc" -eq 0 ] && [ -f "$work/with space/CLAUDE.md" ]'
check "unrelated files are untouched" '[ "$(cat "$work/with space/notes.txt")" = "keep me" ]'

echo
if [ "$fails" -eq 0 ]; then echo "all tests passed"; else echo "$fails test(s) failed"; exit 1; fi
