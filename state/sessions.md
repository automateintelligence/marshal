# Monitored sessions

One row per Claude Code session Marshal watches. Marshal updates this file on every pass.
Names follow `docs/naming.md`. The full session id lives HERE only, never in what Marshal
tells the owner. Last-message ids let a new Marshal session pick up exactly where the old one
stopped.

| Canonical name | Where (tmux session:window, or machine) | Id (from the transcript file name) | Status | Last checked | Plain-language note |
|---|---|---|---|---|---|
| **[PROJECTA] BUILD: example feature -server** | tmux `projecta:1` on the server | `00000000-0000-0000-0000-000000000000` | idle, waiting on the owner (question 2 of 3) | 2026-01-01 09:00 | EXAMPLE ROW, delete it. Building the example feature; PR open, checks green. |

## Retired or parked

- (none yet)
