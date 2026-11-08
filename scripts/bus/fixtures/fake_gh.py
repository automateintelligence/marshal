#!/usr/bin/env -S python3 -I
"""A fake `gh` for the GitHub adapter tests. It never touches the network.

Every call is appended to $FAKE_GH_LOG as one JSON line: {"argv": [...], "stdin": "..."}.
The answer comes from the first route in $FAKE_GH_ROUTES (a JSON list) that matches:
  {"method": "GET", "path": "<regex, full match on the path with its query string>",
   "if_none_match": "<header value, optional>", "file": "<file printed as the output>",
   "exit": <exit code, default 0>, "sleep": <seconds before answering, optional>}
With no matching route it prints an error on stderr and exits 1.
"""

import json
import os
import re
import sys
import time

argv = sys.argv[1:]
stdin = "" if sys.stdin is None or sys.stdin.isatty() else sys.stdin.read()
with open(os.environ["FAKE_GH_LOG"], "a") as log:
    log.write(json.dumps({"argv": argv, "stdin": stdin}) + "\n")

method, path, headers = "GET", None, {}
i = 1 if argv[:1] == ["api"] else 0
while i < len(argv):
    arg = argv[i]
    if arg in ("-X", "--method"):
        method, i = argv[i + 1], i + 2
    elif arg in ("-H", "--header"):
        key, _, value = argv[i + 1].partition(":")
        headers[key.strip().lower()] = value.strip()
        i += 2
    elif arg == "--input":
        i += 2
    elif arg.startswith("-"):
        i += 1
    else:
        path, i = arg, i + 1

with open(os.environ["FAKE_GH_ROUTES"]) as fh:
    routes = json.load(fh)
for route in routes:
    if route.get("method", "GET") != method or path is None:
        continue
    if not re.fullmatch(route["path"], path):
        continue
    if (
        "if_none_match" in route
        and headers.get("if-none-match") != route["if_none_match"]
    ):
        continue
    if route.get("sleep"):
        time.sleep(route["sleep"])
    with open(route["file"], newline="") as fh:
        sys.stdout.write(fh.read())
    sys.exit(route.get("exit", 0))
sys.stderr.write(f"fake gh: no route for {method} {path}\n")
sys.exit(1)
