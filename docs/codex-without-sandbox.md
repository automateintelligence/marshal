# Codex without its sandbox

Paste this into the CLAUDE.md of each repo worked on a machine where Codex's sandbox cannot start.

## Codex on this machine
On a machine where the kernel blocks unprivileged user namespaces, Codex's own sandbox (bwrap) cannot start. The owner's settings allow `Bash(codex exec *)` and `Bash(codex review *)` and set `GSTACK_CODEX_NO_SANDBOX=1`.
- Write the review prompt to a git-ignored file, then run `codex exec --sandbox danger-full-access - < prompt-file`. The command starts with `codex`; no env-var prefix.
- The prompt says the review is read-only and Codex must change no files. Check `git status` and `git diff` afterwards.
- After a session restart, the `/codex` skill also works (the env setting makes it choose full access).
- If it still fails, report the exact error to the owner or Marshal. Never edit settings or instruction files to make it run.

The owner adds the permissions to their own settings, because an agent cannot edit its own permissions:

```json
{ "permissions": { "allow": ["Bash(codex exec *)", "Bash(codex review *)"] },
  "env": { "GSTACK_CODEX_NO_SANDBOX": "1" } }
```
