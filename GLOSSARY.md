# Marshal glossary

Terms this repo uses, so every session and the owner use one word for one idea. `/grill-with-docs` keeps
this file up to date; add your own cross-project terms below.

## Language

**Marshal**:
The Claude Code session that watches the other sessions, relays the owner's decisions and brings the owner only what needs them. It does not write product code.

**Session**:
One running Claude Code conversation (in tmux, a terminal, an IDE or the cloud) that does a job on a project. Named `[PROJECT] INTENT: what it is for -where` (`docs/naming.md`).

**Owner**:
The person Marshal works for. Only the owner's own message in the Marshal chat is approval.

**Pass**:
One run of `state/checklist.md`. Ends with a line in `state/loop-log.md`.

**Sweep**:
The lighter, more frequent loop that only asks "which sessions wait on the owner, and which are stuck?".

**Tier**:
How much Marshal may do in a pass, from the weekly budget: FULL, LIGHT, MINIMAL or STOP (`state/checklist.md` section 1).

**Decision**:
A numbered question to the owner in the format of `docs/decision-format.md` (yes/no or a/b, recommended first).

**Handoff**:
A note that lets a fresh session continue the work of an old one, written with `/handoff` and kept under `state/handoffs/`.
