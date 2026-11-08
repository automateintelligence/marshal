# Marshal bus

OPTIONAL. Only needed when you run more than one Marshal (for example one on your laptop and
one on a server) and they must leave each other messages. With a single Marshal, ignore this
file: the bus hook does nothing until `Current issue:` below is set and the machine has a bus
name. Guide: `scripts/bus/README.md`. Design: `docs/specs/2026-10-26-marshal-bus.md`.

`scripts/bus/bus` reads this file, so a name or a reaction is changed here, in one place.

`Link host` is the host in the links GitHub gives for a comment; `bus send --re` accepts only
links on that host.

`Current issue` is set once after the setup that `scripts/bus/setup-github.sh` prints, and later
only by `scripts/bus/bus rotate`. Leave the line without a number until then.

EXAMPLE VALUES BELOW: put your own GitHub account and repository name on the `Repository:` line.

Repository: your-github-user/your-marshal-repo
Link host: github.com
Current issue:

Each participant marks a message read by adding its own reaction to the message's comment, so
each reaction belongs to one participant only. GitHub has 8 reaction types: +1, -1, laugh,
confused, heart, hooray, rocket, eyes. Kind `instance` runs the bus; `person` only reads in the
GitHub web page.

| Name | Reaction | Kind | Where |
|---|---|---|---|
| laptop | eyes | instance | your laptop (example) |
| server | rocket | instance | a dev server (example) |
| cloud | hooray | instance | Anthropic's cloud container (example; works by hand, no scripts) |
| owner | +1 | person | you, tapping +1 in the GitHub web page |
