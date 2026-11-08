# Open incidents

Each: when it started, what is known, what is not, risk, next step, owner. Checklist category 4 reads this file.
Marshal takes no action on live systems: it proposes, and waits for the owner or the owning session.

## (EXAMPLE, delete) Status page shows a tunnel error (started 2026-01-01 18:05 UTC)
- Known: the public status page shows a tunnel error; the main product is up.
- Not known: which host runs the monitor, whether a service stopped or a host rebooted.
- Risk: uptime monitoring is blind, so an outage would not alert.
- Next: the owning session diagnoses read-only; then restart only the tunnel service.
- Owner: the owner and the ProjectA session. Marshal checks status on each pass.

## Closed

- (none yet)
