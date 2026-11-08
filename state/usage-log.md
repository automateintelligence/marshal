# Usage log

One line each time the weekly percent has moved 1 point or more since the last line, or the weekly or 5-hour reading became or stopped being stale or absent. Written by `scripts/usage/usage-courier.sh`. Times are UTC with local time in brackets.
"week" is the weekly limit for all models. "5-hour" is the rolling 5-hour limit.
"stale" means the statusline file was more than 90 minutes old, so there was no current reading.
"absent" means the statusline did not report that limit, or its reset time had already passed.

