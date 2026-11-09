# Marshal

Marshal is one Claude Code session that manages your other Claude Code sessions. You keep doing the work in
as many sessions as you like (different projects, different repos, tmux windows on a server or local). 

Marshal:
- watches them (tmux panes, transcripts, repos, PRs),
- relays your decisions to the right session via messaging,
- makes the easy calls for you under rules you set, and says so,
- asks you the hard questions as short y/n or labeled a/b/c questions in plain language with context 
  and consequences of the decisions,
- keeps what it knows in `state/*.md`, committed to git, so a restart or a new machine loses nothing,
- never writes product code itself.

Marshal has two parts:

1. **The plugin** (installed from the marketplace into Claude Code). It goes to EVERY session you run, in any repo: a SessionStart hook hands each session the worker rules in `docs/worker-rules.md` (how to ask you questions, review loops, reporting, naming, no flaky tests), so you do not edit `~/.claude/CLAUDE.md`. It also carries four skills written by Matt Pocock and copied unmodified from his repo [mattpocock/skills](https://github.com/mattpocock/skills) (MIT): `/marshal:handoff`, `/marshal:grilling`, `/marshal:grill-with-docs` and `/marshal:domain-modeling`; see Credits. It adds the command `/marshal:init` that creates your workspace.
2. **Your Marshal workspace.** Your own repo, PRIVATE, holding `CLAUDE.md`, `state/` and `docs/` for the Marshal session itself. Create it with `/marshal:init`, or use the public Marshal repo (github.com/automateintelligence/marshal) as a template.

## How it works day to day

An example from the owner who built it, who runs three to seven projects at once.

- **The setup.** Each project has one or more Claude Code sessions in tmux on a dev server, named like `[PROJ] PLAN: video pipeline -server`. One more session is Marshal. The owner mostly talks to Marshal, from the terminal or a phone, and only drops into a project session when they want to.
- **The rhythm.** Every 30 minutes Marshal checks every session; every hour it runs its checklist. When a session finishes something, asks a question or goes quiet, Marshal finds out and acts.
- **Saving time.** Easy calls Marshal makes itself, inside fences the owner set (nothing merged to main, nothing live, no loosened checks), and records each one where the owner can reverse it. Harder calls get a second opinion from Codex first. Only real decisions reach the owner, one short numbered list, in project priority order, answerable as "1a 2y 3n". Marshal never stacks a new question on an unanswered one, so the owner is not interrupted.
- **Pacing the weekly limit.** Marshal reads usage every hour and keeps to a daily share (about one seventh of the week per day). When a day runs hot it parks the lowest-priority work at a safe point; when the week is ending with budget left, it gives sessions more room so the limit is used, not wasted. Long experiments keep running through any stop.
- **Focus across projects.** The owner keeps one picture of everything without holding it in their head: what is ready to merge, what waits on them, and why. Work keeps moving while they are in class or asleep; a morning list says what happened and what needs them. In one Saturday, six project sessions turned out about 45 reviewed pull requests this way, while the owner was in class for most of it.

## Install

### Claude Code

1. Add the marketplace (once):

   ```
   /plugin marketplace add automateintelligence/marketplace
   ```

2. Install the plugin. When Claude Code asks for a scope, pick **user**, so every session you run gets it:

   ```
   /plugin install marshal@automateintelligence
   ```

3. Restart Claude Code, or run `/reload-plugins`.

4. Create your workspace: a new folder with Marshal's rules and your `state/`. Claude copies the templates, runs `git init`, installs a push guard and walks you through the `{{placeholders}}`:

   ```
   /marshal:init ~/marshal
   ```

5. Put the workspace in your own PRIVATE repo (replace `<you>` with your GitHub name):

   ```
   cd ~/marshal && git init && git add -A && git commit -m "Marshal workspace" && gh repo create <you>/my-marshal --private --source . --remote github --push
   ```

   Never fork the public Marshal repo for your workspace (a fork of a public repo is public), and never push your filled-in `state/` to the public Marshal repo.

6. Start Marshal in that folder with Remote Control (`<where>` is `local`, `wsl`, `srv` or `cloud`), then paste the two loop prompts from [The two loops](https://github.com/automateintelligence/marshal#the-two-loops):

   ```
   cd ~/marshal && claude --remote-control '[MSL] OPS: Marshal -<where>'
   ```

Template route, instead of steps 4 and 5 (the public Marshal repo is the template; the plugin from steps 1 to 3 still gives every session the worker rules):

```
gh repo create <you>/my-marshal --private --template automateintelligence/marshal --clone
cd my-marshal && sh scripts/install-git-hooks.sh
```

Then follow [Without the plugin](https://github.com/automateintelligence/marshal#without-the-plugin-use-this-repo-as-a-template) from step 2.

Then start your other sessions in tmux windows and name them per `docs/naming.md` (`[PROJECTA] BUILD: login page -srv`). Marshal finds them with `tmux ls`.
Let Marshal read tmux without asking each time: add read-only rules to your Claude Code permission settings, for example
`Bash(tmux ls*)`, `Bash(tmux list-windows *)` and `Bash(tmux capture-pane *)`. Leave `tmux send-keys` (how it messages
a session) on ask until you trust it.

### OpenAI Codex

OpenAI Codex: not supported yet. See [ROADMAP.md](https://github.com/automateintelligence/marshal/blob/main/ROADMAP.md).

## Keeping your state private

Your filled-in `state/` holds notes about your work. It must live only in your own PRIVATE repo.

- Make your own private repo (install step 5, or the template route). Never fork the public Marshal repo for your workspace: a fork of a public repo is public. Never push your filled-in `state/` to the public Marshal repo.
- `/marshal:init` makes a fresh repo with no history and no remote, and installs a git `pre-push` guard (`scripts/git-hooks/pre-push`; template users run `sh scripts/install-git-hooks.sh`). The guard refuses any push to github.com/automateintelligence/marshal (https or ssh, with or without `.git`). It also refuses a push to any repo GitHub reports as public when `state/` differs from the shipped templates. That check needs the `gh` CLI; without `gh` the guard blocks only the public Marshal repo and prints a warning.
- In the public Marshal repo, a GitHub Actions check (`.github/workflows/guard-state.yml`) fails any pull request that changes `state/` unless it carries the `template-change` label.

## Optional: permanent worker rules, Codex second opinion

- **Permanent worker rules instead of the hook.** The plugin already hands the rules to every session. If you prefer a permanent block in `~/.claude/CLAUDE.md` (it also works without the plugin), run from your workspace: `sh scripts/install-worker-rules.sh` (dry run, writes nothing), then `sh scripts/install-worker-rules.sh --apply`. It keeps a backup, and the plugin's hook then stays silent so nothing is doubled.
- **Codex as a second opinion** on a machine where Codex's own sandbox cannot start: see [docs/codex-without-sandbox.md](docs/codex-without-sandbox.md).

## What you need

| Needed | For |
|---|---|
| [Claude Code](https://claude.com/claude-code) | Marshal and the sessions it watches |
| `tmux` | Marshal reads other sessions' screens (`tmux capture-pane`) and can message them |
| `git` and the `gh` CLI (logged in: `gh auth login`) | state is committed and pushed to your private repo; PRs and issues are read with `gh`; the push guard asks `gh` whether a repo is public |
| `sh`, `awk`, `sed`, `grep` | the plugin's SessionStart hook and `/marshal:init` (POSIX, no other dependencies) |
| `python3` | the tests, and the optional bus |
| `jq`, GNU `date`, `flock`, `cron` | the optional usage recorder (hourly budget reading) |
| Codex CLI (optional) | a second opinion before Marshal decides for you (`state/checklist.md` section 12) |

Developed and tested on Linux and WSL. The usage recorder uses GNU `date` and `flock`, which stock macOS does not have.

## Without the plugin: use this repo as a template

Use this when you do not want the plugin for the workspace (or after the template route in the install steps above).

1. **Make your own PRIVATE repo from this one.** Marshal commits and pushes `state/`, which will hold notes about
   your work. `gh repo create <you>/my-marshal --private --template automateintelligence/marshal --clone`, then
   `cd my-marshal && sh scripts/install-git-hooks.sh` (the push guard). Cloning this repo and pointing its remote at your
   own private repo also works; run `sh scripts/install-git-hooks.sh` there too. Never fork this repo for your workspace and never push
   your state to it (see "Keeping your state private").
2. **Fill in the placeholders.** `grep -rn '{{' CLAUDE.md state docs` lists them. The important ones are in
   `CLAUDE.md`: your name, your timezone, your daily schedule, your weekly-limit reset time, your project ranking.
   Or let Claude do it: start `claude` in the repo and say *"Read README.md and CLAUDE.md, then interview me
   one question at a time to fill every {{placeholder}}, and edit the files."*
3. **Fill in `state/priorities.md` and `state/sessions.md`.** Delete the EXAMPLE rows in every `state/` file as you go.
   Edit `docs/naming.md` so the project codes (the `[PROJECTA]` part) match yours.
4. **Install the worker rules** (skip this when the plugin is installed: its hook does it). Every session Marshal watches
   should follow the same short rules (how to ask you questions, what counts as your approval, review loops, wind-down).
   A project's `CLAUDE.md` only loads in that project's own folder, so these rules must go into each user's global
   `~/.claude/CLAUDE.md`. Preview with `scripts/install-worker-rules.sh` (dry run, writes nothing), then run
   `scripts/install-worker-rules.sh --apply`. It inserts `docs/worker-rules.md` between marker lines and keeps a backup.
   Run it on every machine. An example global file is in `docs/example-global-CLAUDE.md`.
5. **Start Marshal.** Run `claude` in this repo, preferably inside tmux (on a dev box or your own machine), and turn
   on Remote Control (the `/remote-control` command in recent Claude Code versions) so you can answer from your phone. First message:
   *"Resume Marshal. Read docs/RESUME.md first."*
6. **Start your other sessions in tmux windows** (see above), then **paste the two loop prompts** into the Marshal session (below).

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
.claude-plugin/plugin.json  the plugin manifest (name: marshal)
hooks/hooks.json          SessionStart hook: hands the worker rules to every session
commands/init.md          /marshal:init: creates your workspace
ROADMAP.md                what is planned, including Codex
CLAUDE.md                 Marshal's rules (template: fill the placeholders)
GLOSSARY.md               Marshal's own terms
docs/RESUME.md            how to pick Marshal back up after a restart
docs/decision-format.md   how Marshal asks you things (1a 2y 3n)
docs/naming.md            how sessions are named: [PROJECT] INTENT: what -where
docs/owner-agent-workflow.md  your model/effort router and review rules (example, edit)
docs/worker-rules.md      the rules block every monitored session carries
docs/example-global-CLAUDE.md  example personal ~/.claude/CLAUDE.md (edit)
docs/codex-without-sandbox.md  running Codex where its sandbox cannot start
docs/usage-recorder-spec.md   why the budget recorder works the way it does
docs/specs/               design of the optional bus
state/                    everything Marshal knows (templates with one EXAMPLE line each)
  checklist.md              the loop: budget gate, repo scan, needs-you, sessions, hygiene, reporting
  sessions.md priorities.md decisions.md watch.md budget.md usage.md loop-log.md
  projects.md repos.md incidents.md morning-brief-template.md bus.md
scripts/usage/            hourly budget reading from the statusline (no model call), with tests
scripts/bus/              OPTIONAL: messages between several Marshals through one GitHub issue, with tests
scripts/session-start-worker-rules.sh  the hook's script: prints the worker rules as JSON, nothing if ~/.claude/CLAUDE.md already has them
scripts/init-workspace.sh      what /marshal:init runs: copies the templates, git init, installs the push guard
scripts/git-hooks/pre-push     the push guard (and state-templates.manifest, the list of shipped state/ files)
scripts/install-git-hooks.sh   install the push guard into a repo (template users run it once)
scripts/make-state-manifest.sh regenerate the manifest after editing state/
scripts/install-worker-rules.sh  insert docs/worker-rules.md into ~/.claude/CLAUDE.md (dry run first; test_install_worker_rules.sh)
scripts/install-user-skills.sh   copy the vetted skills into ~/.claude/skills (template clones without the plugin)
.claude/skills/           grill-with-docs, grilling, domain-modeling, handoff by Matt Pocock (mattpocock/skills, MIT, see SOURCES.md and Credits); the plugin ships them
.claude/settings.json     hook for the optional bus (does nothing until the bus is set up)
.github/workflows/guard-state.yml  fails a PR here that changes state/ without the template-change label
```

## Optional pieces

- **Budget recorder.** Gives Marshal a free hourly reading of your weekly limit so its budget gate does not depend on
  you pasting `/usage`. Install steps are in the header comments of `scripts/usage/statusline-sensor.sh` (wrap your
  statusline) and `scripts/usage/usage-push.sh` (one hourly cron line). `usage-push.sh` pushes to the git remote
  `origin` on `main`; set `MARSHAL_REMOTE` and `MARSHAL_BRANCH` for others. Why it is built this way:
  `docs/usage-recorder-spec.md`. Without it, Marshal asks you to paste `/usage` at most once a day and runs in the LIGHT tier.
- **Skills.** The plugin ships them as `/marshal:handoff`, `/marshal:grilling`, `/marshal:grill-with-docs` and `/marshal:domain-modeling`. In a template clone without the plugin, `scripts/install-user-skills.sh` copies the skills in `.claude/skills/` into `~/.claude/skills` so they work in every project.
- **Bus.** Only if you run more than one Marshal (say, laptop and server). See `scripts/bus/README.md`.
- **Adding the recorder or the bus to a workspace made by `/marshal:init`:** run `/marshal:init <same folder>` again and answer yes. It copies only the missing files and never overwrites yours (`scripts/init-workspace.sh <folder> --with-usage` or `--with-bus` does the same from a shell).

## Tests

```
python3 -I scripts/usage/test_usage_recorder.py
python3 -I scripts/bus/test_bus.py
sh scripts/test_install_worker_rules.sh
sh scripts/test_session_start_hook.sh
sh scripts/test_init_workspace.sh
sh scripts/test_git_guard.sh
sh scripts/test_guard_state_workflow.sh
```

No network and no real clock: the suites use fakes, local repositories and fixed times.

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
   settings, because an agent cannot edit its own permissions (details: `docs/codex-without-sandbox.md`):
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
15. **Unsent text the owner typed is their decision.** Relay it by message. Never type keystrokes into a draft they are still editing.
16. **Read a session's full output on a sweep, not only its input line.** Stalled sessions (API errors, cut-off replies) get a nudge without asking.
17. **The auto-mode checker may refuse a relay** that authorizes a deploy, a settings change or a close. Do not work around it; give the owner the exact text to send themselves.

## Credits

- **Matt Pocock** wrote the four skills Marshal ships: `grill-with-docs`, `grilling`, `domain-modeling` (with its `GLOSSARY-FORMAT.md` and `ADR-FORMAT.md`) and `handoff`. They come from his repository [github.com/mattpocock/skills](https://github.com/mattpocock/skills) and are copied unmodified under its MIT license, Copyright (c) 2026 Matt Pocock. The license text travels with the copies in `.claude/skills/LICENSE-mattpocock-skills.txt`, and `.claude/skills/SOURCES.md` records exactly which upstream folders each skill came from and when. The grilling approach (rounds of numbered questions with a recommended answer, keeping a glossary and decision records up to date as you go) is his. Marshal's only addition is the rule that every question stays answerable as y/n or a/b/c. If these skills help you, star and follow his repo; later versions land there first.
