# Budget

Plan: {{PLAN}} (for example Pro, Max 5x, Max 20x).
Week resets at a fixed instant: {{WEEK_RESET}} (example: "Sunday 05:00 UTC, which is Saturday 21:00 in
America/Los_Angeles in winter"). Use `resets_at` from the usage recorder (`docs/usage-recorder-spec.md`),
never a hard-coded local hour: the local hour shifts when daylight-saving time changes.

Rule: by the end of day N of the week, use at most N/7 of it. Day 1 is the first day after the weekly
reset, day 7 is the day the week resets. Marshal's tiers (FULL, LIGHT, MINIMAL, STOP) are defined in
`state/checklist.md` section 1 and take their numbers from this rule and the newest reading.

## Readings

The usage recorder (`scripts/usage/`) writes the newest reading to `state/usage.md`. Without the
recorder, the owner pastes the output of `/usage` and Marshal adds a row here.

| When (local time) | Week, all models | Session (5-hour) | Day N | N/7 line | Verdict |
|---|---|---|---|---|---|
| 2026-01-01 09:00 (EXAMPLE, delete) | 12% | 3% | 2 | 29% | Headroom 17 points. FULL tier. |

## Notes

- Add per-model limits here if your plan has them (for example a smaller weekly limit for the most expensive model).
