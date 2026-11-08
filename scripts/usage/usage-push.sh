#!/usr/bin/env bash
# Usage recorder, step 3 of 3: the hourly job. Pull, record a reading, commit, push.
#
#   scripts/usage/usage-push.sh
#
# In order: (1) git pull --rebase from the remote (MARSHAL_REMOTE, default origin) and branch
# (MARSHAL_BRANCH, default main); (2) run usage-courier.sh, which rewrites state/usage.md and
# may append a line to state/usage-log.md; (3) commit ONLY those two files; (4) git push to that
# remote and branch. It never forces a push. If anything fails it prints one line on stderr and
# exits 1, and the next hourly run tries again (a commit that could not be pushed is pushed by
# the next run, after it pulls and rebases).
#
# Only one run at a time: it holds a lock (usage-push.lock in the git folder) from start to
# finish, and a run that finds the lock taken prints one line and exits 0. Before pulling it
# discards uncommitted changes to its own two files (left behind when a commit failed; the
# courier writes them again). It refuses to run on any branch other than the configured one (main by default), and it fails
# when the checkout has any OTHER modified tracked file (git will not pull with changes in the
# way). So run it from a checkout that nothing else edits. Untracked files are left alone and
# never committed.
#
# It never waits for a password: pull and push each get 60 seconds (USAGE_PUSH_TIMEOUT, in
# seconds, changes that), terminal prompts are off, Git Credential Manager is told not to
# prompt, and an ssh remote runs ssh in batch mode. A run that times out exits 1, within about
# 7 seconds of the limit, after killing every process the timed-out git command started.
#
# Install (once, after reading the two scripts):
#   1. Run it by hand and confirm it pushes without asking for a password:
#        <CHECKOUT>/scripts/usage/usage-push.sh
#   2. crontab -e, add this one line (every hour on the hour; it is quiet unless something fails):
#        0 * * * * <CHECKOUT>/scripts/usage/usage-push.sh >> <HOME>/.cache/claude/usage-push.log 2>&1
#      (<CHECKOUT> is where you cloned this repo, <HOME> is your home folder, both absolute.)
# The sensor (statusline-sensor.sh, see its header) must be installed too, or the reading is
# always "stale". Needs: git, jq, GNU date, timeout (coreutils), flock (util-linux).
set -euo pipefail

remote="${MARSHAL_REMOTE:-origin}"
branch="${MARSHAL_BRANCH:-main}"
files=(state/usage.md state/usage-log.md)
limit="${USAGE_PUSH_TIMEOUT:-60}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GIT_TERMINAL_PROMPT=0 # cron cannot answer a password prompt; fail instead of hanging

fail() { echo "usage-push: $*" >&2; exit 1; }

# Network git commands: bounded in time, never prompting. credential.interactive is read by
# Git Credential Manager; plain git ignores it. timeout puts git in a process group of its own
# (its id is timeout's pid) and on time-out sends SIGTERM to that group, but it returns as soon
# as git itself exits. A child of git that ignores SIGTERM (credential helper, ssh, alias) would
# live on, so after a failure whatever is left of the group gets SIGTERM, 2 seconds, then
# SIGKILL. The lock (fd 9) is closed for git, so no child can ever hold it.
net_git() {
  local pid rc=0
  timeout -k 5 "$limit" git -c credential.interactive=never "$@" 9>&- &
  pid=$!
  wait "$pid" || rc=$?
  if [ "$rc" -ne 0 ] && kill -TERM -- "-$pid" 2>/dev/null; then
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 -- "-$pid" 2>/dev/null || break
      sleep 0.2
    done
    kill -KILL -- "-$pid" 2>/dev/null || true
  fi
  return "$rc"
}

is_ssh_url() {
  case "$1" in
    ssh://* | git+ssh://* | ssh+git://*) return 0 ;;
    *::* | *://*) return 1 ;;
    *:*) [[ "${1%%:*}" != */* ]] ;; # scp-like user@host:path
    *) return 1 ;;
  esac
}

rebase_in_progress() {
  [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]
}

cd "$(cd "$here/../.." && pwd)"

exec 9>"$(git rev-parse --git-path usage-push.lock)"
if ! flock -n 9; then
  echo "usage-push: another run holds the lock, so this run did nothing"
  exit 0
fi

[ "$(git rev-parse --abbrev-ref HEAD)" = "$branch" ] \
  || fail "this checkout is not on $branch, so nothing was written"

if is_ssh_url "$(git remote get-url "$remote" 2>/dev/null || true)" \
  || is_ssh_url "$(git remote get-url --push "$remote" 2>/dev/null || true)"; then
  GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-$(git config --get core.sshCommand || echo ssh)} -o BatchMode=yes"
  export GIT_SSH_COMMAND
fi

mapfile -t leftover < <(git diff --name-only HEAD -- "${files[@]}")
if [ "${#leftover[@]}" -gt 0 ]; then
  git restore --source=HEAD --staged --worktree -- "${leftover[@]}"
fi

if net_git pull -q --rebase "$remote" "$branch"; then
  :
else
  rc=$?
  if rebase_in_progress; then git rebase --abort 2>/dev/null || true; fi
  [ "$rc" -eq 124 ] && fail "git pull --rebase from $remote $branch timed out after ${limit}s, so nothing was written; the next run retries"
  fail "git pull --rebase from $remote $branch failed, so nothing was written; the next run retries"
fi

"$here/usage-courier.sh" 9>&-

git add -- "${files[@]}"
if git diff --cached --quiet -- "${files[@]}"; then
  exit 0
fi

written="$(sed -n 's/^Written: \([^ ]*\) .*/\1/p' state/usage.md)"
msg="state/usage.md: usage reading $written"$'\n\n'"state/usage.md:1-$(wc -l < state/usage.md)"
if ! git diff --cached --quiet -- state/usage-log.md; then
  msg+=$'\n'"state/usage-log.md:$(wc -l < state/usage-log.md)"
fi
msg+=$'\n'"- Automatic hourly reading from scripts/usage/usage-courier.sh."
git commit -q -m "$msg" -- "${files[@]}" 9>&- \
  || fail "git commit failed; the next run discards the uncommitted reading and tries again"

if net_git push -q "$remote" "HEAD:$branch"; then
  :
else
  rc=$?
  [ "$rc" -eq 124 ] && fail "git push to $remote $branch timed out after ${limit}s; the commit stays local and the next run retries"
  fail "git push to $remote $branch failed; the commit stays local and the next run retries"
fi
