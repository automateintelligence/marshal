#!/usr/bin/env -S python3 -I
"""Fake adapter for the Marshal bus: a directory-backed double of adapter-github.py, for tests.

Same contract as the real one (docs/specs/2026-10-26-marshal-bus.md section 12): one operation
per run, named by the first argument (send, list-since, mark-read, open-channel, close-channel);
one JSON object in on stdin; one JSON object out on stdout; exit 0 on success; exit 1 with
{"error": {"kind": K, "message": M, "retry_after": seconds or null}} on failure.

Everything lives in $MARSHAL_BUS_FAKE_DIR:
  store.json   {"next_ref": 10, "next_channel": 2, "channels": {"1": {"state": "open",
               "title": "...", "items": [{"ref": "10", "created": "<UTC>", "body": "...",
               "reads": [{"mark": "eyes", "at": "<UTC>"}]}]}}}
  faults.json  optional, {"<op>": [entry, ...]}. Each call of <op> uses the first entry and
               counts down its "times" (-1 means forever). An entry may hold:
                 "kind" (with "message", "retry_after"): answer with that error;
                 "store": true (send only): store the item first, then answer with the error;
                 "malformed": true: print something that is not JSON and exit 0;
                 "inject": {"channel", "body", "state"}: change the store first, then go on.
  calls.jsonl  one line per call: {"op": ..., "input": {...}}.
Times come from MARSHAL_BUS_NOW. Links look like
https://fake.invalid/<space>/issues/<channel>#issuecomment-<ref>. The state is always read fresh,
so the list-since input fresh_state changes nothing here.
"""

import fcntl
import json
import os
import sys
from datetime import datetime, timezone
from typing import NoReturn


def now_text():
    return os.environ.get("MARSHAL_BUS_NOW") or datetime.now(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )


def link(space, channel, ref):
    return f"https://fake.invalid/{space}/issues/{channel}#issuecomment-{ref}"


def fail(kind, message, retry_after=None) -> NoReturn:
    print(
        json.dumps(
            {"error": {"kind": kind, "message": message, "retry_after": retry_after}}
        )
    )
    sys.exit(1)


def cursor_ref(cursor):
    if cursor is None:
        return 0
    try:
        return int(json.loads(cursor)["ref"])
    except (ValueError, KeyError, TypeError):
        fail("rejected", "the cursor is not one this adapter made")


def take_fault(base, op):
    path = os.path.join(base, "faults.json")
    if not os.path.exists(path):
        return None
    with open(path) as fh:
        faults = json.load(fh)
    queue = faults.get(op) or []
    if not queue:
        return None
    entry = queue[0]
    times = entry.get("times", 1)
    if times != -1:
        if times <= 1:
            queue.pop(0)
        else:
            entry["times"] = times - 1
    with open(path, "w") as fh:
        json.dump(faults, fh)
    return entry


def main():
    op = sys.argv[1] if len(sys.argv) > 1 else ""
    base = os.environ.get("MARSHAL_BUS_FAKE_DIR")
    if not base:
        fail("rejected", "MARSHAL_BUS_FAKE_DIR is not set")
    data = json.loads(sys.stdin.read() or "{}")
    with open(os.path.join(base, "calls.jsonl"), "a") as log:
        log.write(json.dumps({"op": op, "input": data}) + "\n")
    with open(os.path.join(base, "store.json.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        store_path = os.path.join(base, "store.json")
        with open(store_path) as fh:
            store = json.load(fh)
        fault = take_fault(base, op) or {}
        inject = fault.get("inject")
        if inject:
            target = store["channels"][inject["channel"]]
            if inject.get("body") is not None:
                ref = str(store["next_ref"])
                store["next_ref"] += 1
                target["items"].append(
                    {
                        "ref": ref,
                        "created": now_text(),
                        "body": inject["body"],
                        "reads": [],
                    }
                )
            if inject.get("state"):
                target["state"] = inject["state"]
        if fault.get("malformed"):
            save(store_path, store)
            print("this is not JSON")
            return
        result = None
        if not fault.get("kind") or fault.get("store"):
            result = run(op, data, store)
        save(store_path, store)
        if fault.get("kind"):
            fail(
                fault["kind"],
                fault.get("message", f"fake {fault['kind']}"),
                fault.get("retry_after"),
            )
        print(json.dumps(result))


def save(path, store):
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(store, fh, indent=1)
    os.replace(tmp, path)


def channel_of(store, data):
    channel = str(data.get("channel", ""))
    if channel not in store["channels"]:
        fail("not_found", f"no channel {channel}")
    return channel, store["channels"][channel]


def run(op, data, store):
    if op == "send":
        channel, ch = channel_of(store, data)
        ref = str(store["next_ref"])
        store["next_ref"] += 1
        ch["items"].append(
            {"ref": ref, "created": now_text(), "body": data["body"], "reads": []}
        )
        return {"ref": ref, "url": link(data.get("space"), channel, ref)}
    if op == "list-since":
        channel, ch = channel_of(store, data)
        after = cursor_ref(data.get("cursor"))
        limit = max(1, min(100, int(data.get("limit", 100))))
        new = [it for it in ch["items"] if int(it["ref"]) > after]
        more = len(new) > limit
        items = [
            {
                "ref": it["ref"],
                "url": link(data.get("space"), channel, it["ref"]),
                "created": it["created"],
                "body": it["body"],
                "reads": it.get("reads", []),
                "after": json.dumps({"ref": int(it["ref"])}),
            }
            for it in new[:limit]
        ]
        cursor = items[-1]["after"] if items else data.get("cursor")
        return {
            "items": items,
            "cursor": cursor,
            "more": more,
            "channel_state": ch["state"],
        }
    if op == "mark-read":
        channel, ch = channel_of(store, data)
        item = next(
            (it for it in ch["items"] if it["ref"] == str(data.get("ref"))), None
        )
        if item is None:
            fail("not_found", f"no item {data.get('ref')}")
        mark = data.get("mark")
        old = next((r for r in item.setdefault("reads", []) if r["mark"] == mark), None)
        if old is None:
            old = {"mark": mark, "at": now_text()}
            item["reads"].append(old)
        return {"ref": item["ref"], "mark": mark, "at": old["at"]}
    if op == "open-channel":
        number = str(store["next_channel"])
        store["next_channel"] += 1
        store["channels"][number] = {
            "state": "open",
            "title": data.get("title", ""),
            "label": data.get("label"),
            "items": [],
        }
        return {"channel": number}
    if op == "close-channel":
        channel, ch = channel_of(store, data)
        ch["state"] = "closed"
        return {"channel": channel, "state": "closed"}
    fail("rejected", f"unknown operation {op!r}")


if __name__ == "__main__":
    main()
