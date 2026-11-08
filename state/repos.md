# Tracked repos and how to read their activity

Used by checklist category 2. Window = time since the last line in `state/loop-log.md`.

| Repo (GitHub, {{GITHUB_OWNER}}/) | Local clone on this machine | Notes |
|---|---|---|
| project-a-api | ~/programming/project-a-api | EXAMPLE row. Worktrees under .worktrees/ |
| project-a-web | ~/programming/project-a-web | EXAMPLE row. PRs go to the `preview` branch |
| marshal | ~/programming/marshal | Marshal's own state; ignore Marshal's own commits |

## Reading activity from a local session

Fetch first, then per clone (replace `origin` with your remote's name):

```
git -C <clone> fetch -q --all --prune
git -C <clone> log --all --since="<WINDOW, e.g. 90 minutes ago>" --format='%h|%an|%cr|%d|%s' | head -15
git -C <clone> for-each-ref --sort=-committerdate refs/remotes --count=5 --format='%(committerdate:relative) %(refname:short) %(subject)'
gh pr list --repo <owner>/<repo> --state open --json number,title,updatedAt,statusCheckRollup
git -C <clone> status -sb                                 # uncommitted and untracked files
git -C <clone> log --branches --not --remotes --oneline   # commits not pushed anywhere
git -C <clone> stash list
git -C <clone> worktree list
```

The last four show half-finished work that no session has pushed.

## Reading sessions on other machines

Panes can be read read-only over ssh: `ssh <host> 'tmux capture-pane -p -t <session:window>'`.
