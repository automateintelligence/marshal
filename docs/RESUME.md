# How to resume Marshal

Last updated: <date> by <Marshal session name>.

TEMPLATE. Keep this file short and current. A new Marshal session reads it first (CLAUDE.md, "Start here"),
so it must say exactly how to continue after a restart, a power cut or a move to another machine.

## What Marshal is doing right now

<One or two sentences. Example: "Job 1: manage the 3 sessions in `state/sessions.md`. For each: understand it,
say in plain words where it stands, and line up the decisions the owner needs to make.">

## Standing schedule

Two `/loop` jobs, pasted into the Marshal session (see README, "Quick start"):

1. Hourly checklist: `Run the Marshal checklist in state/checklist.md. Stay inside the budget tier it computes. Update state/, commit and push, then report only what changed or needs me.`
2. Sweep every 10 to 30 minutes: `Check all open sessions to see if they are awaiting feedback. Give them to me using your rules in project priority order, but don't interrupt me until I answer previous question. If they are not awaiting feedback, figure out if and why it is stuck and drive progress.`

`/loop` jobs live only in the session that started them. They stop when that session restarts, and in the
version this was written for they also stop after 7 days. FIRST THING after any restart: list the scheduled jobs
(`CronList`), and if there are none, paste both prompts again.

## Known problems

- (none yet) Example: "Cross-session messages can be held when the sender's permission mode differs from the receiver's ('held, waiting for approval in that session's terminal'). Safety rule, not a bug. Approve it in the receiving session, align the modes, or use GitHub issues and PR comments."

## Queued jobs (not started)

- (none yet) Example: "Re-run the disk test monthly." "The overnight cleanup: find half-done sessions and branches, decide keep, finish or kill."

## How Marshal sees sessions

- tmux: `tmux ls` and `tmux capture-pane -p -t <session:window>` (read-only). Check the transcript file
  (`~/.claude/projects/<dir>/<id>.jsonl`) for the truth: screens can be stale.
- Sessions on Remote Control or in the cloud may show up through session-listing tools; poll them by id.
- Local sessions that are not in tmux or on Remote Control are invisible to Marshal until someone tells it.
- Reading transcripts is token-heavy: delegate to a cheaper subagent (model set explicitly) and ask only for the last human and assistant messages.

## Repo layout

- `CLAUDE.md`: rules
- `docs/decision-format.md`: how to ask the owner things
- `docs/naming.md`: how sessions are named
- `state/`: live state (sessions, budget, priorities, decisions, projects, watch list, loop log)
- `scripts/usage/`: the usage recorder (hourly budget reading)
- `scripts/bus/`: optional messages between several Marshals
