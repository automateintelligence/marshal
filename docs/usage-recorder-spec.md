# Usage recorder: spec

Goal: an hourly budget reading in `state/` that costs nothing, so Marshal's budget gate never depends on the owner pasting `/usage`. The scripts are in `scripts/usage/`; this file is why they are built the way they are.

## Why this design

- Documented source of the weekly percent: the statusline command's JSON input (`rate_limits.seven_day.used_percentage`, `rate_limits.seven_day.resets_at`, and `rate_limits.five_hour.*`). Reading it costs no model call.
- A hook is NOT a confirmed source. It could not be confirmed that hook input carries `rate_limits`. So: the statusline command is the sensor; a hook or cron is only the courier.
- `claude -p "/usage"` works but spends some of the weekly limit. Use it only for the twice-daily briefings, as a cross-check against the statusline number. It also shows per-model weekly lines, which the statusline fields may not carry.

## Pieces

1. **Sensor.** A `statusLine` command in `~/.claude/settings.json`. First read the existing setting: if a statusline already exists, wrap it (save stdin, then call the old command with the same input), never replace it. The command adds `captured_at` (UTC, ISO) to the JSON, writes `~/.cache/claude/statusline.json.tmp`, then `mv` to `statusline.json`. It must finish in well under a second and must never fail loudly.
2. **Courier.** A cron job every hour (also fine as a `Stop` hook; either, not both). It reads the file and turns it into one record. Rules:
   - File older than 90 minutes: write `stale` with the file's age, NOT the old percent as if current.
   - A window missing from the JSON (it drops out after its reset time): write `absent`.
   - `resets_at` already in the past: treat as absent.
   - Convert `resets_at` to your local timezone for display, keep the UTC epoch as the truth.
3. **Record.** One file with a single writer: `state/usage.md`, rewritten each run (latest reading, plain language, with the epoch fields). Append a line to `state/usage-log.md` only when the weekly percent changed by 1 point or more, or the stale/absent state changed, so git history does not fill with 24 identical commits a day.
4. **Push.** `git pull --rebase` then commit only those two files, then push to `main`. Only the cron job ever touches them, so conflicts should not happen. If the push fails, retry next hour; never force.
5. **Marshal reads** `state/usage.md` for the budget gate (checklist section 1). A stale file means the gate falls back to LIGHT.

## Known gaps to test on your machine

- Does the desktop app you use run the statusline at all? If not, only terminal sessions refresh the file, and the recorder will show `stale` whenever you work only in the desktop app. (One observed case: the Claude Desktop app did not run it; terminal `claude` sessions did.)
- Several sessions write the file: last writer wins, which is fine because the percent is account-wide.
- A second machine has its own statusline and its own file. Take the newest `captured_at`. Only one machine should run the hourly push, so only one writer touches `state/usage.md`.
- cron can be restricted on hardened servers (`/etc/cron.allow`); if `crontab -e` refuses your user, that is why.
- Show the cron's test output to the owner, with the date it ran, before calling it done.

## The week reset is not "Sunday 22:00 forever"

The weekly reset is a fixed instant (for example Sunday 05:00 UTC). In a local timezone the hour shifts when daylight-saving time changes. Always use `resets_at`, never a hard-coded local hour.

## Cheaper subagents

`/usage` can show that most of a week went to general-purpose subagents and suggest a cheaper model. A subagent inherits the parent's model unless one is passed. Every Marshal subagent call sets `model` explicitly, following the owner's router in `docs/owner-agent-workflow.md` (searching and recon: a mid-size model such as sonnet, medium effort). `/usage` can also point at long-running sessions and large user-level instruction files as cost drivers: a Marshal session that has run for days re-reads a very long conversation on every loop, so start a fresh Marshal from a handoff now and then.
