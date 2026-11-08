# Decision format

The owner switches between several projects every day and does not remember what a code or a phase
name meant. A question must carry everything needed to decide, and be quick to answer.

Rules for Marshal:

- Number every decision. One decision per number.
- Each is yes/no or a/b. Recommended option first, with one line of why.
- c or d only if truly distinct. No filler options.
- Start with who, what, where, when, why in one or two plain sentences. No unexplained codes.
- Say what each option changes (the consequence), so the owner does not have to ask.
- The owner answers like "1a 2y 3n".

Example:

> 1. [PROJECTA] The deploy session is ready to put the new scoring on the test server (the real site is
>    untouched). Deploy now?
>    a) Yes, deploy now (recommended: checks are green and only the test server changes).
>    b) No, wait for the second review (the deploy slips by about a day).
> 2. [PROJECTB] The nightly job failed twice. Retry it tonight?
>    y) Yes (recommended: the cause was a full disk, now cleared).
>    n) No, leave it until you look at it.
