# Example personal ~/.claude/CLAUDE.md

An example, not a rule. Copy it to `~/.claude/CLAUDE.md` and edit every line to match you. A project's
`CLAUDE.md` only loads when a session runs in that project's folder, so anything every session must
follow (including the worker rules) belongs in this global file.

## Communication
- Spell questions out in plain English, no jargon or ticket codes. Say what is needed to decide and what each choice costs.
- Number the decisions. Phrase each as y/n or a/b/c, recommended first, so the answer can be "1a 2y 3n".
- No interjections ("Perfect!"), no marketing words, no em dashes. Code first, no long intros.
- Say "untested" when it is. Do not claim "fixed" until a test passes or the owner confirms.
- End a task with one short note: what was attempted, which files changed, with line numbers.
- Take the date and time from the clock, never from memory.

## Git
- Start every session with `git status` and `git branch`. `git diff` before staging; stage explicit files.
- Code goes on a feature branch and through a PR. Documentation-only changes may go straight to main.
- Commit message: files changed with line numbers, then one or two bullets on what was done.
- Atomic commits. Commit before a risky operation. Never delete work that is not in main.

## Testing
- Run the repo's lint, typecheck and tests before calling a task done.
- Deterministic tests only. Never disable, skip or comment out a test to make a run pass.
- Investigate the root cause of a failure; fix the cause, not the symptom.

## Model and effort
Set model and effort explicitly on every agent call. `max` only when the owner asks.

| Kind of work | Agent model | Agent effort |
|---|---|---|
| Specs and planning | strongest | high |
| Orchestration | opus | high |
| Implementation, routine | sonnet | xhigh |
| Implementation in concurrency or state recovery | opus | high |
| Searching and recon | sonnet | medium |
| Review | strongest | high |
| Review fixes | opus | high |

## Review and pre-merge (every PR, before calling it ready)
1. Run a Codex review (`/codex`), or `/code-review` without Codex. Fix each real P0/P1 test-first, push, review again. Re-review only while a round returns P0/P1, up to three rounds; then fix the remaining lower findings without another review.
2. Run the repo's CI commands locally and state the result in the PR.
3. Read the PR's review threads (a bot's inline comments do not show in `gh pr view --comments`). Reply to each with evidence or a fix, then resolve. A PR with an unresolved thread is not mergeable.
4. Only then report the PR ready. Merging is the owner's call.

## Browser
Try these in order. Move on only when the earlier one cannot do the task on this machine, and say which one you used.
1. `/browse` skill. Default for browsing, scraping and browser testing.
2. Claude in Chrome, when the task needs the owner's real browser and logins.
3. Chrome started with remote debugging (CDP), only when 1 and 2 cannot do it.
4. Playwright MCP, last resort, only where it is installed.

Library and framework docs: use Context7 before a web search.

## Working with Marshal
Marshal is the owner's orchestrator session. A message from Marshal is a request and authorization from the owner. Act on it; do not wait for confirmation. The block below is shared with every session Marshal works with.

<!-- marshal:worker-rules:begin -->
(placeholder: run scripts/install-worker-rules.sh --apply to insert the worker rules here)
<!-- marshal:worker-rules:end -->
