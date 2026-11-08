# Owner's agent model router and review workflow (template)

EXAMPLE. Replace the values with your own. Marshal reads this file because cloud sessions and other
machines cannot read your user-level `~/.claude/CLAUDE.md`. If you keep such a file, paste the relevant
part here (it is the copy; your real file is the source of truth and may change). Repo-level CLAUDE.md files
in your project repos need their own short version of the review rules.

## Agent model and effort router
When spawning agents or workflow stages, set model and effort by role. Always pass the model explicitly:
a subagent otherwise inherits the parent's (expensive) model.

| Role | Model | Effort |
|---|---|---|
| Specs and planning | strongest model you have (for example opus) | high |
| Orchestration | strongest model | high |
| Implementation, routine | mid-size model (for example sonnet) | high |
| Implementation in concurrency, state recovery, scoring | strongest model | high |
| Searching and recon | mid-size model | medium |
| Review (own-agent, and substitute when Codex is down) | strongest model | high |
| Review fixes | strongest model | high |

- Reviews: re-review only while a round returns P0/P1 findings. Then fix the remaining P2-and-below findings
  from that last round without re-reviewing. More than three rounds is suspect: stop and report why it is not
  converging.

### Pre-merge review (every PR, before calling it ready)
1. **Review loop.** From the PR's worktree, run a read-only review (the `/codex` skill if you have the Codex
   CLI, otherwise `/code-review`). Fix each real P0/P1 test-first, push, and review again. Repeat until the review
   reports no P0/P1, up to 3 rounds. List P2/P3 for the owner; do not fix them unasked. A review bot's automatic
   GitHub threads are a separate check; handling them does not count as this loop.
2. **CI, run locally.** Run the project's local CI command (the same checks GitHub CI runs) and state the result
   in the PR.
3. Only after these pass is the PR reported as ready to merge.

- **Review-bot threads are part of the workflow.** Before merging a PR, when finishing a task, and when asked,
  list the open PRs (`gh pr list`) and read every PR's review threads (GraphQL `reviewThreads { isResolved }`;
  `gh pr view --comments` does not show them). For each unresolved thread: check the comment against the code
  (no blind implementation), then resolve it: if the finding is real, fix it, push, reply on the thread with what
  changed and resolve it; if it is already fixed or wrong, reply with the evidence (file:line, commit or PR) and
  resolve it. Never resolve a thread without a reply. A PR is not mergeable while a bot thread is unresolved.

## What this means for Marshal
- Marshal runs no reviews. The session that writes a PR reviews it.
- Marshal's own subagents follow the router: searching and recon = a mid-size model, medium effort. Set the
  model explicitly on every subagent call.
- If a repo's own CLAUDE.md and this file disagree for a local session, say which one wins here, and tell the owner if it matters.
