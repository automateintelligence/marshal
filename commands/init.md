---
description: Create your Marshal workspace (a new private-repo-to-be holding Marshal's rules and state/)
argument-hint: "[folder]  (for example ~/marshal-workspace)"
allowed-tools: Bash(sh *init-workspace.sh*)
---

Set up a Marshal workspace: the owner's own folder and own git repository for the Marshal orchestrator session (CLAUDE.md, docs/, state/). The files come from this plugin's own copies. Do not fetch anything from the network and do not clone the public Marshal repo.

Requested folder: `$ARGUMENTS`

1. **Folder.** If the requested folder is empty, ask the owner where to put it and suggest `~/marshal-workspace`. If the folder text contains shell metacharacters (`;`, `|`, `&`, backticks, `$(`), refuse it and say why.

2. **Optional pieces.** Ask two questions in plain words, yes/no, recommended answer first, with the consequence of each:
   - Copy the budget recorder (`--with-usage`)? Recommend no for now: it needs `jq`, GNU `date`, `flock` and a cron line to be useful. Without it Marshal asks the owner to paste `/usage` about once a day. Running this command again later with the flag adds it without touching files already there.
   - Copy the bus (`--with-bus`)? Recommend no unless the owner runs more than one Marshal.

3. **Create it.** Run, with the folder in quotes and the flags the owner chose:

   ```bash
   sh "${CLAUDE_PLUGIN_ROOT}/scripts/init-workspace.sh" "<folder>" [--with-usage] [--with-bus]
   ```

   The script copies the templates (never overwriting an existing file), runs `git init` (a fresh repository: no history, no remote), and installs a `pre-push` guard that refuses pushes to the public Marshal repo and to any public GitHub repo once `state/` is filled in. If it exits non-zero, show its message to the owner and stop. Do not work around a refusal.

4. **Fill in the placeholders.** In the new folder, list them with `grep -rn '{{' CLAUDE.md state docs`. Interview the owner one question at a time (plain language, each answer a short a/b or a typed fact) and edit the files in the new folder. The ones that matter most are in `CLAUDE.md`: the owner's name, timezone, daily schedule, weekly-limit reset time and project ranking. Then: delete the EXAMPLE rows in every `state/` file, set the project codes in `docs/naming.md`, and delete the TEMPLATE comment at the top of `CLAUDE.md`.

5. **Private repo.** Say this plainly: the workspace must live in the owner's own PRIVATE GitHub repo. Never fork the public Marshal repo for it (a fork of a public repo is public) and never push the filled-in `state/` to the public repo. Offer to create it (the owner must give their GitHub name; do not run this without a yes):

   ```bash
   cd "<folder>" && git init && git add -A && git commit -m "Marshal workspace" && gh repo create <you>/my-marshal --private --source . --remote github --push
   ```

6. **Start Marshal.** Tell the owner to start it in that folder with Remote Control, and paste the two loop prompts from `docs/RESUME.md` ("Standing schedule"):

   ```bash
   cd "<folder>" && claude --remote-control '[MSL] OPS: Marshal -<where>'
   ```

Report in plain words: the folder, what was copied, whether the guard was installed, and what is still open.
