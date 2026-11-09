#!/bin/sh
# Tests for the privacy guard: scripts/git-hooks/pre-push, scripts/install-git-hooks.sh and the
# state/ template manifest. Uses throwaway repos, a fake gh and local remotes only: no network.
# Usage: sh test_git_guard.sh   (exit 0 = all pass)

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root="$here/.."
hook="$here/git-hooks/pre-push"
installer="$here/install-git-hooks.sh"
manifest="$here/git-hooks/state-templates.manifest"

work=$(mktemp -d "${TMPDIR:-/tmp}/guard-test.XXXXXX")
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

ZERO=0000000000000000000000000000000000000000

# Fake gh: prints $STUB_VIS (PUBLIC, PRIVATE, INTERNAL) or fails when STUB_VIS=fail. Logs its arguments.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<EOF
#!/bin/sh
echo "\$*" >> "$work/gh.log"
[ "\${STUB_VIS:-}" = fail ] && exit 1
echo "\${STUB_VIS:-PRIVATE}"
EOF
chmod +x "$work/bin/gh"
MARSHAL_GH="$work/bin/gh"; export MARSHAL_GH

# A workspace repo: commit 1 = the shipped templates, commit 2 = filled in, commit 3 = back to templates.
repo="$work/repo"
git init -q -b main "$repo"
mkdir -p "$repo/scripts/git-hooks"
cp -R "$root/state" "$repo/state"
cp "$manifest" "$repo/scripts/git-hooks/"
( cd "$repo" && git add -A && git commit -q -m templates )
sha_pristine=$(git -C "$repo" rev-parse HEAD)
printf 'Client Acme is late on the contract.\n' >> "$repo/state/priorities.md"
( cd "$repo" && git commit -q -am "filled in" )
sha_filled=$(git -C "$repo" rev-parse HEAD)
( cd "$repo" && git revert --no-edit HEAD > /dev/null )
sha_reverted=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" checkout -q "$sha_pristine"
printf 'extra\n' > "$repo/state/extra-notes.md"
( cd "$repo" && git add -A && git commit -q -m "extra file in state" )
sha_extra=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" checkout -q main

# with_vis VISIBILITY URL LOCAL_SHA [REMOTE_SHA]: set what the fake gh answers, then run_hook.
with_vis() { STUB_VIS=$1; export STUB_VIS; shift; run_hook "$@"; }

# run_hook URL LOCAL_SHA [REMOTE_SHA]: call the hook the way git does. Sets rc and err.
run_hook() {
    : > "$work/gh.log"
    err=$(cd "$repo" && printf 'refs/heads/main %s refs/heads/main %s\n' "$2" "${3:-$ZERO}" | sh "$hook" origin "$1" 2>&1 > /dev/null)
    rc=$?
}

# 0. The manifest matches the state/ templates that ship in this repo.
sh "$here/make-state-manifest.sh" > "$work/manifest.now"
check "manifest is current (run scripts/make-state-manifest.sh if this fails)" 'cmp -s "$work/manifest.now" "$manifest"'
check "manifest lists every state/ file" '[ "$(wc -l < "$manifest")" -eq "$(find "$root/state" -type f | wc -l)" ]'

# 1. The public Marshal repo is refused in every spelling, without asking GitHub.
for url in \
    'https://github.com/automateintelligence/marshal' \
    'https://github.com/automateintelligence/marshal.git' \
    'https://github.com/automateintelligence/marshal/' \
    'https://github.com/AutomateIntelligence/Marshal.git' \
    'https://www.github.com/automateintelligence/marshal.git' \
    'https://user:token@github.com/automateintelligence/marshal.git' \
    'git@github.com:automateintelligence/marshal.git' \
    'git@github.com:automateintelligence/marshal' \
    'ssh://git@github.com/automateintelligence/marshal.git' \
    'ssh://git@github.com:22/automateintelligence/marshal.git' \
    'git://github.com/automateintelligence/marshal.git' \
    'github.com/automateintelligence/marshal.git'; do
    with_vis PRIVATE "$url" "$sha_pristine"
    check "refuses $url" '[ "$rc" -eq 1 ] && printf %s "$err" | grep -q "PUBLIC Marshal repo"'
    check "no gh call for $url" '[ ! -s "$work/gh.log" ]'
done
with_vis PRIVATE 'https://github.com/automateintelligence/marshal.git' "$ZERO"
check "refuses the public repo even for a branch deletion line" '[ "$rc" -eq 1 ]'

# 2. Look-alike addresses are not the public repo.
for url in \
    'https://github.com/automateintelligence/marshal-workspace.git' \
    'https://github.com/someone/marshal.git' \
    'https://github.com/automateintelligence/marshal2' \
    'https://github.com/notautomateintelligence/marshal' \
    'https://gitlab.com/automateintelligence/marshal.git'; do
    with_vis PRIVATE "$url" "$sha_filled"
    check "allows look-alike $url" '[ "$rc" -eq 0 ]'
done

# 3. A private remote passes, even with a filled-in state/. gh is asked with the host/owner/repo address.
with_vis PRIVATE 'https://github.com/jane/my-marshal.git' "$sha_filled"
check "private remote with filled state passes" '[ "$rc" -eq 0 ]'
check "gh was asked about github.com/jane/my-marshal" 'grep -q "repo view github.com/jane/my-marshal --json visibility" "$work/gh.log"'
with_vis PRIVATE 'git@github.com:jane/my-marshal.git' "$sha_filled"
check "private remote over ssh passes" '[ "$rc" -eq 0 ]'
with_vis INTERNAL 'https://github.com/acme/my-marshal.git' "$sha_filled"
check "internal (organisation-only) remote passes" '[ "$rc" -eq 0 ]'

# 4. A public remote is refused when state/ differs from the templates.
with_vis PUBLIC 'https://github.com/jane/leaky.git' "$sha_filled"
check "public remote with filled state is refused" '[ "$rc" -eq 1 ] && printf %s "$err" | grep -q "PUBLIC repo on GitHub"'
with_vis PUBLIC 'https://github.com/jane/leaky.git' "$sha_filled" "$sha_pristine"
check "public remote, incremental push of a filled commit, is refused" '[ "$rc" -eq 1 ]'
with_vis PUBLIC 'https://github.com/jane/leaky.git' "$sha_extra"
check "public remote with an extra file in state/ is refused" '[ "$rc" -eq 1 ]'
with_vis PUBLIC 'https://github.com/jane/leaky.git' "$sha_reverted"
check "public remote with a filled commit in the history is refused" '[ "$rc" -eq 1 ]'

# 5. A public remote passes when state/ is still exactly the templates.
with_vis PUBLIC 'https://github.com/jane/fork-of-templates.git' "$sha_pristine"
check "public remote with pristine state passes" '[ "$rc" -eq 0 ]'

# 6. Branch deletions and empty pushes send no state.
with_vis PUBLIC 'https://github.com/jane/leaky.git' "$ZERO" "$sha_filled"
check "public remote, branch deletion, passes" '[ "$rc" -eq 0 ]'
: > "$work/gh.log"
( cd "$repo" && sh "$hook" origin 'https://github.com/jane/leaky.git' < /dev/null ) 2> /dev/null; rc=$?
check "public remote, nothing to push, passes" '[ "$rc" -eq 0 ]'

# 7. Without the manifest, any state/ file counts as different (fails closed).
mv "$repo/scripts/git-hooks/state-templates.manifest" "$work/manifest.hidden"
with_vis PUBLIC 'https://github.com/jane/leaky.git' "$sha_pristine"
check "public remote without a manifest is refused" '[ "$rc" -eq 1 ]'
with_vis PRIVATE 'https://github.com/jane/my-marshal.git' "$sha_pristine"
check "private remote without a manifest passes" '[ "$rc" -eq 0 ]'
mv "$work/manifest.hidden" "$repo/scripts/git-hooks/state-templates.manifest"

# 8. gh missing or unable to answer: warn, block only the public Marshal repo.
saved_gh=$MARSHAL_GH
MARSHAL_GH="$work/no-such-gh"
with_vis PRIVATE 'https://github.com/jane/my-marshal.git' "$sha_filled"
check "gh missing: other remotes pass with a warning" '[ "$rc" -eq 0 ] && printf %s "$err" | grep -q "WARNING"'
run_hook 'https://github.com/automateintelligence/marshal.git' "$sha_filled"
check "gh missing: public Marshal repo still refused" '[ "$rc" -eq 1 ]'
MARSHAL_GH=$saved_gh
with_vis fail 'https://github.com/jane/my-marshal.git' "$sha_filled"
check "gh cannot answer: pass with a warning" '[ "$rc" -eq 0 ] && printf %s "$err" | grep -q "WARNING"'

# 9. Remotes that are not on github.com are not sent to gh.
with_vis PUBLIC "$work/somewhere/remote.git" "$sha_filled"
check "local path remote passes" '[ "$rc" -eq 0 ]'
check "local path remote: gh not called" '[ ! -s "$work/gh.log" ]'
with_vis PUBLIC 'https://gitlab.com/jane/x.git' "$sha_filled"
check "other host passes, gh not called" '[ "$rc" -eq 0 ] && [ ! -s "$work/gh.log" ]'

# 10. --is-public-url mode.
sh "$hook" --is-public-url 'git@github.com:automateintelligence/marshal.git'; rc=$?
check "--is-public-url: yes" '[ "$rc" -eq 0 ]'
sh "$hook" --is-public-url 'https://github.com/jane/my-marshal.git'; rc=$?
check "--is-public-url: no" '[ "$rc" -eq 1 ]'

# 11. The installer.
inst="$work/inst"
git init -q -b main "$inst"
mkdir -p "$inst/scripts"
cp -R "$here/git-hooks" "$inst/scripts/git-hooks"
cp "$installer" "$inst/scripts/"
( cd "$inst" && sh scripts/install-git-hooks.sh ) > "$work/out" 2>&1; rc=$?
check "installer exits 0" '[ "$rc" -eq 0 ]'
check "hook installed and executable" '[ -x "$inst/.git/hooks/pre-push" ]'
check "installed hook equals the tracked copy" 'cmp -s "$inst/.git/hooks/pre-push" "$inst/scripts/git-hooks/pre-push"'
( cd "$inst" && sh scripts/install-git-hooks.sh ) > "$work/out" 2>&1; rc=$?
check "second install says already installed" '[ "$rc" -eq 0 ] && grep -q "Already installed" "$work/out"'
printf '#!/bin/sh\necho mine\n' > "$inst/.git/hooks/pre-push"
( cd "$inst" && sh scripts/install-git-hooks.sh ) > "$work/out" 2>&1; rc=$?
check "a different existing hook is not overwritten (exit 2)" '[ "$rc" -eq 2 ] && grep -q "echo mine" "$inst/.git/hooks/pre-push"'
( cd "$inst" && sh scripts/install-git-hooks.sh --force ) > "$work/out" 2>&1; rc=$?
check "--force replaces it" '[ "$rc" -eq 0 ] && cmp -s "$inst/.git/hooks/pre-push" "$inst/scripts/git-hooks/pre-push"'
check "--force keeps the old hook as pre-push.bak" 'grep -q "echo mine" "$inst/.git/hooks/pre-push.bak"'
mkdir -p "$work/notrepo"
( cd "$work/notrepo" && sh "$installer" ) > "$work/out" 2>&1; rc=$?
check "outside a git repository: exit 2" '[ "$rc" -eq 2 ]'
git -C "$inst" config core.hooksPath "$work/custom-hooks"
( cd "$inst/scripts" && sh install-git-hooks.sh ) > "$work/out" 2>&1; rc=$?
check "core.hooksPath is honoured, from a subfolder" '[ "$rc" -eq 0 ] && [ -x "$work/custom-hooks/pre-push" ]'

# 12. End to end with real git pushes (local remotes only).
e2e="$work/e2e"
git init -q -b main "$e2e"
mkdir -p "$e2e/scripts"
cp -R "$here/git-hooks" "$e2e/scripts/git-hooks"
cp "$installer" "$e2e/scripts/"
cp -R "$root/state" "$e2e/state"
( cd "$e2e" && sh scripts/install-git-hooks.sh > /dev/null && git add -A && git commit -q -m "workspace" )
git init -q --bare "$work/private-remote.git"
git -C "$e2e" remote add private "$work/private-remote.git"
( cd "$e2e" && git push -q private main ) > "$work/out" 2>&1; rc=$?
check "real push to a private (local) remote succeeds" '[ "$rc" -eq 0 ] && git -C "$work/private-remote.git" rev-parse -q --verify refs/heads/main > /dev/null'
mkdir -p "$e2e/github.com/automateintelligence"
git init -q --bare "$e2e/github.com/automateintelligence/marshal.git"
git -C "$e2e" remote add public github.com/automateintelligence/marshal.git
( cd "$e2e" && git push -q public main ) > "$work/out" 2>&1; rc=$?
check "real push to the public Marshal address is refused" '[ "$rc" -ne 0 ] && grep -q "PUSH REFUSED" "$work/out"'
check "nothing reached the public address" '! git -C "$e2e/github.com/automateintelligence/marshal.git" rev-parse -q --verify refs/heads/main > /dev/null'

echo
if [ "$fails" -eq 0 ]; then echo "all tests passed"; else echo "$fails test(s) failed"; exit 1; fi
