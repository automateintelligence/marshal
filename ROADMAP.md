# Marshal roadmap

Plain list of what is planned. Nothing here is done unless it is ticked, and nothing has a date.

## Codex compatibility

OpenAI Codex: not supported yet. Marshal, its hook and `/marshal:init` run on Claude Code only. The sibling plugins
conductor and bubo already install on Codex (0.155.0 and later) from the same marketplace, so this item follows
how they do it.

- [ ] **Install from the marketplace on Codex.** Add a `.codex-plugin/plugin.json` (conductor's points at its skills with
  `"skills": "./skills/"`), then `codex plugin marketplace add automateintelligence/marketplace` and
  `codex plugin add marshal@automateintelligence`. Update the install steps and the Codex status line in this README
  and in the marketplace README.
- [ ] **Worker rules delivered to Codex sessions.** Either a Codex hook (bubo runs a SessionStart hook on Codex; Codex asks
  the user to approve a plugin's hooks once) or a block in the user's `AGENTS.md`. `scripts/install-worker-rules.sh`
  already takes `--target FILE`, so pointing it at an `AGENTS.md` may work today; that is untested. Keep the check that
  injects nothing when the rules are already installed.
- [ ] **Marshal reading Codex sessions.** Finding sessions with `tmux ls` and `tmux capture-pane` works the same. The
  transcript is somewhere else and has another format (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, not
  `~/.claude/projects/<dir>/<id>.jsonl`). Teach `CLAUDE.md` ("Reading sessions") and `state/checklist.md` both.
- [ ] **Codex-safe command names.** Codex reserves `/` for its own commands, and Codex plugins cannot add slash commands.
  Make `/marshal:init` a skill as well, called `$marshal:init` on Codex, with the same behaviour.
- [ ] **Test on Codex.** Install from a local marketplace, run the hook and the init skill on a real Codex, and add
  Codex's hook input and output format to the test fixtures.

## Other near-term items

- [ ] **Say what changed when the worker rules change.** The hook reads `docs/worker-rules.md` at every session start, so a
  plugin update changes every session. Add a rules version to the injected text and tell the owner when an update
  changes the rules.
- [ ] **Upgrade a workspace.** `/marshal:init` copies the templates once and never overwrites. When the templates change
  (a new checklist section, a new `state/` file), add a command that shows the difference and applies what the owner accepts.
- [ ] **Cloud and Remote Control session polling.** Marshal sees tmux sessions. Sessions in the cloud or on Remote Control
  need a documented, cheap way to poll them by id (README, lesson 13).
- [ ] **Budget reader portability.** The usage recorder needs GNU `date` and `flock`, which stock macOS does not have.
  Replace them with portable commands, or document a different reader.
- [ ] **Tests in CI.** Only the `state/` guard runs on GitHub today. Run the five test scripts and
  `claude plugin validate --strict` on every pull request.
