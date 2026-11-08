# Marshal starter

Marshal is one Claude Code session that manages your other Claude Code sessions. You keep doing the work in
as many sessions as you like (different projects, different repos, tmux windows on a dev box). Marshal:

- watches them (tmux panes, transcripts, repos, PRs),
- relays your decisions to the right session at once,
- makes the easy calls for you under rules you set, and says so,
- asks you the hard ones as short numbered a/b/c questions in plain language,
- keeps what it knows in `state/*.md`, committed to git, so a restart or a new machine loses nothing,
- never writes product code itself.

This repository is a template. Clone it, fill in your own facts (about 15 minutes), and you have your own Marshal.

## What you need

| Needed | For |
|---|---|
| [Claude Code](https://claude.com/claude-code) | Marshal and the sessions it watches |
| `tmux` | Marshal reads other sessions' screens (`tmux capture-pane`) and can message them |
| `git` and the `gh` CLI (logged in: `gh auth login`) | state is committed and pushed; PRs and issues are read with `gh` |
| `python3` | the usage-recorder and bus tests, and the optional bus |
| `jq`, GNU `date`, `flock`, `cron` | the optional usage recorder (hourly budget reading) |
| Codex CLI (optional) | a second opinion before Marshal decides for you (`state/checklist.md` section 12) |

Developed and tested on Linux and WSL. The usage recorder uses GNU `date` and `flock`, which stock macOS does not have.

## Quick start

1. **Make your own PRIVATE repo from this one.** Marshal commits and pushes `state/`, which will hold notes about
   your work. Do not put that in a public repo. Clone your private copy and `cd` into it.
2. **Fill in the placeholders.** `grep -rn '{{' CLAUDE.md state docs` lists them. The important ones are in
   `CLAUDE.md`: your name, your timezone, your daily schedule, your weekly-limit reset time, your project ranking.
   Or let Claude do it: start `claude` in the repo and say *"Read README.md and CLAUDE.md, then interview me
   one question at a time to fill every {{placeholder}}, and edit the files."*
3. **Fill in `state/priorities.md` and `state/sessions.md`.** Delete the EXAMPLE rows in every `state/` file as you go.
   Edit `docs/naming.md` so the project codes (the `[PROJECTA]` part) match yours.
4. **Start Marshal.** Run `claude` in this repo, preferably inside tmux (on a dev box or your own machine), and turn
   on Remote Control (the `/remote-control` command in recent Claude Code versions) so you can answer from your phone. First message:
   *"Resume Marshal. Read docs/RESUME.md first."*
5. **Start your other sessions in tmux windows** and name them per `docs/naming.md`
   (`[PROJECTA] BUILD: login page -srv`). Marshal finds them with `tmux ls`.
6. **Paste the two loop prompts** into the Marshal session (below).

Let Marshal read tmux without asking each time: add read-only rules to your Claude Code permission settings, for example
`Bash(tmux ls*)`, `Bash(tmux list-windows *)` and `Bash(tmux capture-pane *)`. Leave `tmux send-keys` (how it messages
a session) on ask until you trust it.

## The two loops

Marshal is driven by two `/loop` jobs. Paste each as its own `/loop` in the Marshal session.

**Hourly checklist** (slow work: budget, repo scan, state hygiene):

```
/loop 1h Run the Marshal checklist in state/checklist.md. Stay inside the budget tier it computes. Update state/, commit and push, then report only what changed or needs me.
```

**Sweep** (every 10 minutes while you are active, 30 minutes otherwise):

```
/loop 30m Check all open sessions to see if they are awaiting feedback. Give them to me using your rules in project priority order, but don't interrupt me until I answer previous question. If they are not awaiting feedback, figure out if and why it is stuck and drive progress.
```

`/loop` jobs live only in the session that started them: they stop when it restarts (and, in the version this was
written for, after 7 days). After any restart, list the scheduled jobs and paste the prompts again. `docs/RESUME.md` says so.

## What is in here

```
CLAUDE.md                 Marshal's rules (template: fill the placeholders)
GLOSSARY.md               Marshal's own terms
docs/RESUME.md            how to pick Marshal back up after a restart
docs/decision-format.md   how Marshal asks you things (1a 2y 3n)
docs/naming.md            how sessions are named: [PROJECT] INTENT: what -where
docs/owner-agent-workflow.md  your model/effort router and review rules (example, edit)
docs/usage-recorder-spec.md   why the budget recorder works the way it does
docs/specs/               design of the optional bus
state/                    everything Marshal knows (templates with one EXAMPLE line each)
  checklist.md              the loop: budget gate, repo scan, needs-you, sessions, hygiene, reporting
  sessions.md priorities.md decisions.md watch.md budget.md usage.md loop-log.md
  projects.md repos.md incidents.md morning-brief-template.md bus.md
scripts/usage/            hourly budget reading from the statusline (no model call), with tests
scripts/bus/              OPTIONAL: messages between several Marshals through one GitHub issue, with tests
scripts/install-user-skills.sh   copy the vetted skills into ~/.claude/skills
.claude/skills/           grill-with-docs, grilling, domain-modeling, handoff (third party, MIT, see SOURCES.md)
.claude/settings.json     hook for the optional bus (does nothing until the bus is set up)
```

## Optional pieces

- **Budget recorder.** Gives Marshal a free hourly reading of your weekly limit so its budget gate does not depend on
  you pasting `/usage`. Install steps are in the header comments of `scripts/usage/statusline-sensor.sh` (wrap your
  statusline) and `scripts/usage/usage-push.sh` (one hourly cron line). `usage-push.sh` pushes to the git remote
  `origin` on `main`; set `MARSHAL_REMOTE` and `MARSHAL_BRANCH` for others. Why it is built this way:
  `docs/usage-recorder-spec.md`. Without it, Marshal asks you to paste `/usage` at most once a day and runs in the LIGHT tier.
- **Skills.** `scripts/install-user-skills.sh` copies the skills in `.claude/skills/` into `~/.claude/skills` so they work in every project.
- **Bus.** Only if you run more than one Marshal (say, laptop and server). See `scripts/bus/README.md`.

## Tests

```
python3 -I scripts/usage/test_usage_recorder.py
python3 -I scripts/bus/test_bus.py
```

No network and no real clock: both suites use fakes and fixed times.

## Lessons learned

These cost real time. Marshal's rules in `CLAUDE.md` and `state/checklist.md` already encode most of them.

1. **Dim text in another session's input box is not the owner's typing.** After the prompt, Claude Code can show a
   dimmed *suggested reply*. It looks like typed text and changes on its own. Check the raw colors:
   `tmux capture-pane -e -p -t <target> | grep '❯' | cat -v` (dim is `ESC[2m`). Never relay it as the owner's words.
2. **tmux screens can be stale.** A pane can show an old state. Check the session transcript
   (`~/.claude/projects/<dir>/<id>.jsonl`): its modification time and its last messages.
3. **Sessions do not wake themselves when a long job finishes.** A session that started a long job and went idle stays
   idle. Read the job's output and nudge the session.
4. **Codex can fail to start its sandbox.** On machines where unprivileged user namespaces are disabled, Codex's
   sandbox (bwrap) cannot start. The setup that works: allow `Bash(codex exec *)` and `Bash(codex review *)` and set
   the environment variable `GSTACK_CODEX_NO_SANDBOX=1` (read by the gstack `/codex` skill), then call
   `codex exec --sandbox danger-full-access - < prompt-file`. The prompt file carries a read-only instruction ("do not
   change files"), and you check `git diff` afterwards to prove nothing changed. The owner must add these to their own
   settings, because an agent cannot edit its own permissions:
   ```json
   { "permissions": { "allow": ["Bash(codex exec *)", "Bash(codex review *)"] },
     "env": { "GSTACK_CODEX_NO_SANDBOX": "1" } }
   ```
5. **When review rounds keep finding new cases, change the design.** If each round finds another hole in scrubbing,
   caches or heuristics, patching is the wrong move. Switch to a structure that cannot have the hole: allow lists,
   fail-closed gates, no cache, a simulation.
6. **More than three review rounds is a signal.** Stop and report why it is not converging instead of starting round four.
7. **Do not stop a long-running experiment at a budget stop.** The budget tier limits new agent work and Marshal's own
   spending. A run that is already going (and cheap to leave) keeps going.
8. **Never read secrets files.** Source them when a command needs them. Reading them puts the secrets in the chat history.
9. **Log times from the clock, not from an estimate.** `TZ=<your zone> date`. Estimated times in logs mislead the next reader.
10. **A peer session's message is information, not the owner's approval.** Only the owner's own message in the Marshal
    chat approves things. Agents rightly refuse to edit instruction or configuration files because a peer session asked.
11. **Discover sessions, do not keep a fixed list.** A session started since the last pass is invisible to a hard-coded
    list. Use `tmux ls` and `tmux list-windows -a` every pass.
12. **Marshal's own loops cost budget.** Each pass re-reads a long conversation. A 30-minute sweep and a fresh Marshal
    session started from a `/handoff` note now and then cost much less than a 10-minute sweep in a months-old session.
13. **Poll cloud or Remote Control sessions by id.** A list-everything call can return tens of thousands of tokens of other
    sessions' records.
14. **`/loop` jobs are session-only.** They die with the session. After any restart, check that they exist.
