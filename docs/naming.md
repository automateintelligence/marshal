# Session naming convention

Every session gets a name of this shape, and Marshal always says sessions this way (never "session 6"):

    [PROJECT] INTENT: what it is for -where

Example: `[PROJECTA] DEPLOY: scoring changes to the test server -srv`

The project codes, intent words and location tags below are EXAMPLES. Edit the tables to fit your projects,
then keep them stable: Marshal and every session use them.

## Project codes (the bracket)

| Code | Project | Repos |
|---|---|---|
| PROJECTA | ProjectA (the web app) | project-a-api, project-a-web |
| PROJECTB | ProjectB (the data pipeline) | project-b |
| PROJECTC | ProjectC (a side project) | project-c |
| MSL | Marshal itself | marshal |

## Intent words (one only)

| Word | Means |
|---|---|
| PLAN | decide what to build and how; produces a spec or plan, no code |
| BUILD | write new code or features |
| FIX | repair a bug or failed thing |
| DEPLOY | put something live on a server |
| REVIEW | check someone else's work or a plan |
| RESEARCH | find something out; produces a written answer |
| RUN | babysit a long job or experiment |
| OPS | server, backup, account or admin chores |
| CLEAN | tidy up half-finished work, branches or sessions |

The part after the colon is plain words, under about 8 words, no codes.

## Location tag (the part after the last hyphen)

| Tag | Where the session runs |
|---|---|
| -cloud | Anthropic's cloud container (survives your laptop being off; no access to your machines) |
| -local | On your own computer |
| -wsl | On your computer, in WSL (the Linux side of Windows) |
| -srv | On a server you own (use a more specific tag, for example `-buildbox`, when you have several) |

Add your own tags (one per machine) to this table.

**Why a hyphen, not an at sign:** the session messaging tool treats `name@something` as a team address and
rejects it ("must be a bare teammate name"), so a session titled `... @srv` could not be messaged. Write the
tag with a hyphen.

## Rules

- Name a session in its first minute. Rename it when its job changes (a session that did PLAN and moves to BUILD gets a new name).
- If you cannot pick one intent word, the session is doing two jobs: split it.
- Marshal puts the full session id in `state/sessions.md` only, never in what it tells the owner.
- Marshal may rename sessions to match this convention (reversible; titles only).
