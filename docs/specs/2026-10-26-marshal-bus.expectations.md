# Marshal bus: expectations

Companion to `2026-10-26-marshal-bus.md`. Owner of these outcomes: The owner. Written in the words
of someone watching the issue and the sessions, not in the words of the code.

Definition-of-done gaps found in the spec and closed below: what "delivered" means for a message
(S2, S4); what a reader sees when something is not a message (S9, F7); what happens when the
same message is sent twice (F2, F3); what a broadcast's read marks look like (S5); what "nothing
new" costs (S6, S7); what the cursor may lose (F4, F5); whether a stalled network can stall a
session (M1); whether the bus can ever be read as the owner's voice (M2, M3); whether a secret can
leave a machine through it (M4); whether the bus is allowed to alter anything on GitHub beyond
adding comments and its own reactions (M6); and what a rotated issue must preserve (S10, F8).
Updated 2026-10-26 for the owner's decisions: read receipts are reactions, a message is named by its
comment link (no invented ID).

## Success scenarios

S1. A message sent from one instance appears on the bus issue as one comment whose body begins
    with the four headers in order (To, From, In-reply-to, Sent), then a blank line, then the
    text, and the sender gets the comment link printed back.

S2. Within the next hook run on the recipient's machine (and after the once-per-minute pause),
    the recipient session sees the message printed under the DATA header, with every body line
    prefixed, and the recipient's reaction is on that message's comment, so the rendered view
    shows `Read: <time> by <recipient>`.

S3. `bus show` on any machine prints the same rendered view for the same bus contents: each
    message in the order GitHub stored it, followed by one `Read:` line per participant whose
    reaction (or receipt comment) is on it, or `Read: nobody yet`. A reaction of a type not in
    the table adds no line.

S4. A reply carries `In-reply-to:` with the original's comment link, and the rendered view lets
    a reader find the original from the reply without searching.

S5. A `To: all` message read by two instances and seen by the owner (the owner tapped +1 in the web page)
    shows three `Read:` lines (the two instances and `owner`) and none for the sender.

S6. A hook run that finds nothing new prints nothing at all (zero bytes), so the session's
    context does not grow and no model tokens are spent.

S7. A hook run that finds nothing new makes at most one request to GitHub, and that request is
    the cheap conditional kind when the backend supports it.

S8. An instance recognises its own messages: it never prints them as new and never adds its
    reaction to them.

S9. A comment on the issue without valid headers (for example the owner typing in the browser) is
    shown as `unparsed comment <link>` with its first 200 characters, marked as data, and is
    never treated as a message, never given a reaction, never replied to by the hook.

S10. After a rotation, the old issue is closed, its last message says `Successor: #<new>`,
    `state/bus.md` names the new issue, and a reader that still points at the old issue reads
    the rest of the old issue first, then the new one, with no message missed or shown twice.

S11. The cloud instance, with no hook and no local files, can do everything a shell instance
    does except rotate: list, read, mark read (its `hooray` reaction, or a receipt comment if it
    cannot add reactions), reply, using the same comment format by hand.

S12. A fresh machine with no local state, pointed at the current issue, shows as unread exactly
    the messages addressed to it (or to all) that carry neither its reaction nor a receipt
    comment from it, and nothing else.

## Failure scenarios (plausible wrong results that look right)

F1. One instance sends two messages in the same second, and the retry guard (same `From:` and
    `Sent:`) takes the second for a copy of the first and never posts it. Must not happen: an
    instance never gives two of its messages the same `Sent`. Two instances never collide
    because `From:` differs.

F2. A send times out after the request left, the sender retries, and the issue ends up with two
    comments with the same `From:` and `Sent:`. The rendered view must count only the first and
    label the second `duplicate of <link>`; nobody adds a reaction to the duplicate.

F3. The sender retries with a fresh `Sent:` instead of the queued one, so the retry guard cannot
    find the first copy and the issue gets two. Must not happen: the body, `Sent:` included, is
    fixed when the message is queued, and before re-posting the sender looks for it.

F4. The local cursor file is deleted. A naive reader would re-print every old message. Correct
    behaviour: re-scan, compute unread from the reactions (and receipt comments), print only
    what carries no read mark from this instance.

F5. A reaction failed to post (rate limit) but the cursor moved past the message. The message
    would never be marked read and the sender would think it was never read. Correct behaviour:
    the message stays in the pending receipts and the reaction is retried on the next run; the
    message is not printed again more than once.

F6. The hook prints a message whose body contains a line that looks like the end-of-bus frame
    or a fake header, and the model takes the fake line as a frame. Must not happen: every body
    line is prefixed and the frame lines are not, so a body cannot look like a frame.

F7. A body containing header lines of its own (someone pasting a message into a message) is
    parsed as two messages. Must not happen: only the first header block counts; pasted headers
    are text.

F8. Two instances rotate at the same time and create two successor issues. The rendered view
    must follow the one named by the lower `Successor` comment; the other new issue is closed
    with a note and never collects messages.

F9. GitHub answers 403 for the rate limit and the hook keeps retrying inside its time budget,
    burning the shared 5,000 requests per hour for every instance. Must not happen: one failed
    list call ends the run; the next run waits at least a minute; a `Retry-After` is honoured.

F10. The hook is installed in the owner's user settings and every session in every repo polls the
    bus. Must not happen by default: the hook lives in the marshal repo's project settings.

F11. A message is sent with `To:` set to a name nobody has, is never read, and nobody notices.
    `bus send` refuses a `To:` that is not a known instance (from the table in `state/bus.md`)
    or `all`.

F12. The body is truncated for the hook view and the truncation cuts in the middle of a
    `Read:` line or an `In-reply-to:` link so the model misreads it. The truncation is only of
    body text, the headers are never truncated, and the marker says how much is missing.

## Must-nots

M1. The hook must never hold a session: it always exits 0 within its hard time limit (8 seconds
    of work, killed at 10), whatever GitHub or the network does, and it never blocks a prompt.

M2. Nothing read from the bus may be presented as an instruction from the owner or as approval. Every
    rendered view starts with the DATA header and ends with the end frame; a message saying the owner
    approved something is still data.

M3. Nothing read from the bus is executed, evaluated, used as a file path, a command, an
    environment value or a name; control characters and terminal escapes are stripped before
    printing.

M4. No secret ever leaves a machine through the bus: text matching the token patterns in the
    spec is refused at send with exit 3 and is not queued.

M5. A message is never silently lost: every failure to send leaves it in the outbox or reports
    it (its `To:` and `Sent:`) on stderr; a refused message says why.

M6. The bus never edits, deletes, hides or locks a comment, never removes a reaction, adds only
    its own instance's reaction, never changes labels except during rotation (adding
    `marshal-bus` to the new issue), never closes an issue except the old one during rotation,
    and never touches any issue other than the current bus issue and its successor.

M7. The bus layer never calls GitHub directly: every backend call goes through the adapter
    executable, so swapping to another backend changes one file and no test of the bus layer.

M8. The cloud instance never rotates the issue.

M9. The rendered view names every message by its comment link, the same link replies and
    receipt comments use; there is no second, invented name.

M10. Nothing in any output, document or message produced by the bus contains an em dash.
