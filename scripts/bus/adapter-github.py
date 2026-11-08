#!/usr/bin/env -S python3 -I
"""GitHub adapter for the Marshal bus. The only part of the bus that talks to GitHub, through
the `gh` command (gh api), which already holds the login on each machine.

Contract (docs/specs/2026-10-26-marshal-bus.md section 12): one operation per run, named by the
first argument; one JSON object in on stdin; one JSON object out on stdout; exit 0 on success;
on failure exit 1 with {"error": {"kind": K, "message": M, "retry_after": seconds or null}},
K one of offline, rate_limited, auth, not_found, rejected, unknown. Stateless: everything it
needs is in the input. Common input: space ("owner/repo"), channel (issue number),
deadline_seconds.

  send           {body} -> {ref, url}                       POST issues/<n>/comments
  list-since     {cursor, limit, fresh_state} -> {items, cursor, more, channel_state}
                 GET issues/<n>/comments (conditional on the stored ETag), GET issues/<n> for the
                 open or closed state when something is new, when the kept state is 10 minutes
                 old or more, or when fresh_state is true, and one read-only GraphQL query per
                 100 comments that carry reactions, for who reacted with what and when
  mark-read      {ref, mark} -> {ref, mark, at}             POST issues/comments/<id>/reactions
  open-channel   {title, body, label} -> {channel}          POST issues (rotation only)
  close-channel  {} -> {channel, state}                     PATCH issues/<n> state=closed (rotation)

It never edits or deletes a comment, never removes a reaction, never touches labels except the
one given when it creates a successor issue, and never locks anything.
The opaque cursor holds the last comment id seen, its creation time (used as `since`), the ETag
of the last list that found nothing new, and the issue's last known state with when it was read.
A write that fails without an HTTP answer is `unknown` (it may have reached GitHub), except for
the failures that happen before anything is sent (DNS, connection refused, TLS handshake).
"""

import json
import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone

REACTIONS = ("+1", "-1", "laugh", "confused", "heart", "hooray", "rocket", "eyes")
GRAPHQL_CONTENT = {
    "THUMBS_UP": "+1",
    "THUMBS_DOWN": "-1",
    "LAUGH": "laugh",
    "CONFUSED": "confused",
    "HEART": "heart",
    "HOORAY": "hooray",
    "ROCKET": "rocket",
    "EYES": "eyes",
}
REACTIONS_QUERY = (
    "query($ids: [ID!]!) { nodes(ids: $ids) { ... on IssueComment { databaseId "
    "reactions(first: 100) { nodes { content createdAt } } } } }"
)
SPACE_RE = re.compile(r"^[A-Za-z0-9_.-]{1,100}/[A-Za-z0-9_.-]{1,100}$")
NUMBER_RE = re.compile(r"^[1-9][0-9]{0,15}$")
LABEL_RE = re.compile(r"^[a-z0-9-]{1,50}$")
TIME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
HEAD_END_RE = re.compile(r"\r?\n\r?\n")
MAX_BODY = 65000
PAGE = 100
STATE_MAX_AGE = 600  # seconds before the issue's open or closed state is read again
# What gh prints when the request never left this machine: its DNS message, a failed dial
# (refused, unreachable, timed out while connecting), a failed TLS handshake.
NOT_SENT = ("error connecting to", "dial tcp", "no such host", "handshake")


class Fail(Exception):
    def __init__(self, kind, message, retry_after=None):
        super().__init__(message)
        self.kind, self.message, self.retry_after = kind, message, retry_after


def now_epoch():
    fixed = os.environ.get("MARSHAL_BUS_NOW")
    if fixed:
        return (
            datetime.strptime(fixed, "%Y-%m-%dT%H:%M:%SZ")
            .replace(tzinfo=timezone.utc)
            .timestamp()
        )
    return time.time()


class Response:
    def __init__(self, status, headers, body):
        self.status, self.headers, self.body = status, headers, body

    def json(self):
        try:
            return json.loads(self.body)
        except ValueError:
            raise Fail(
                "unknown", f"GitHub answered {self.status} with a body that is not JSON"
            )

    def message(self):
        try:
            obj = json.loads(self.body)
        except ValueError:
            obj = None
        text = obj.get("message") if isinstance(obj, dict) else None
        if (
            isinstance(obj, dict)
            and isinstance(obj.get("errors"), list)
            and obj["errors"]
        ):
            first = obj["errors"][0]
            if isinstance(first, dict) and first.get("message"):
                text = f"{text}: {first['message']}" if text else first["message"]
        return f"HTTP {self.status}: {text}" if text else f"HTTP {self.status}"


def parse(raw):
    """gh api -i output: a status line, headers, a blank line, the body. None if no status line
    (gh could not get an HTTP answer at all)."""
    if not raw.startswith("HTTP/"):
        return None
    split = HEAD_END_RE.search(raw)
    head, body = (raw[: split.start()], raw[split.end() :]) if split else (raw, "")
    lines = head.splitlines()
    parts = lines[0].split()
    if len(parts) < 2 or not parts[1].isdigit():
        return None
    headers = {}
    for line in lines[1:]:
        key, sep, value = line.partition(":")
        if sep:
            headers[key.strip().lower()] = value.strip()
    return Response(int(parts[1]), headers, body)


class GitHub:
    def __init__(self, data):
        self.deadline = time.monotonic() + float(data.get("deadline_seconds") or 20)
        self.space = str(data.get("space", ""))
        if not SPACE_RE.match(self.space) or ".." in self.space:
            raise Fail("rejected", f"space must be owner/repo, not {self.space!r}")

    def run(self, method, path, body=None, headers=(), read=None):
        """One gh api call. read: a timeout or a server error means nothing changed (offline);
        for writes it is unknown, because the request may have gone through."""
        read = method == "GET" if read is None else read
        remaining = self.deadline - time.monotonic()
        if remaining < 0.3:
            raise Fail("offline", "no time left before the deadline")
        argv = ["gh", "api", "-i"]
        if method != "GET":
            argv += ["-X", method]
        for header in headers:
            argv += ["-H", header]
        if body is not None:
            argv += ["--input", "-"]
        argv.append(path)
        env = dict(
            os.environ,
            GH_PROMPT_DISABLED="1",
            GH_NO_UPDATE_NOTIFIER="1",
            NO_COLOR="1",
            CLICOLOR="0",
            GH_PAGER="cat",
        )
        try:
            proc = subprocess.Popen(
                argv,
                stdin=subprocess.PIPE if body is not None else subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                start_new_session=True,
            )
        except FileNotFoundError:
            raise Fail(
                "auth",
                "the gh command was not found on this machine; install it and run "
                "gh auth login",
            )
        try:
            out, err = proc.communicate(
                json.dumps(body).encode() if body is not None else None,
                timeout=remaining,
            )
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            proc.communicate()
            raise Fail(
                "offline" if read else "unknown",
                f"GitHub did not answer within {remaining:.0f} seconds",
            )
        resp = parse(out.decode("utf-8", "replace"))
        if resp is None:
            text = (out + err).decode("utf-8", "replace")
            if proc.returncode == 4 or "gh auth login" in text:
                raise Fail(
                    "auth", "gh is not logged in on this machine (run gh auth login)"
                )
            first = text.strip().splitlines()[:1]
            sent = not any(mark in text.lower() for mark in NOT_SENT)
            raise Fail(
                "unknown" if sent and not read else "offline",
                f"no answer from GitHub: {first[0][:200] if first else 'gh failed'}",
            )
        self.check(resp, read)
        return resp

    def check(self, resp, read):
        status = resp.status
        if 200 <= status < 300 or status == 304:
            return
        message = resp.message()
        if status in (403, 429):
            retry = resp.headers.get("retry-after", "")
            if retry.isdigit():
                raise Fail("rate_limited", message, int(retry))
            reset = resp.headers.get("x-ratelimit-reset", "")
            if resp.headers.get("x-ratelimit-remaining") == "0" and reset.isdigit():
                raise Fail(
                    "rate_limited", message, max(1, int(reset) - int(now_epoch()))
                )
            if status == 429 or "rate limit" in message.lower():
                raise Fail("rate_limited", message, 60)
            raise Fail("auth", message)
        if status == 401:
            raise Fail("auth", message)
        if status == 404:
            raise Fail("not_found", message)
        if status >= 500:
            raise Fail("offline" if read else "unknown", message)
        raise Fail("rejected", message)

    def channel(self, data, key="channel"):
        value = str(data.get(key, ""))
        if not NUMBER_RE.match(value):
            raise Fail("rejected", f"{key} must be an issue number, not {value!r}")
        return value

    # Operations

    def send(self, data):
        number = self.channel(data)
        body = data.get("body")
        if not isinstance(body, str) or not body:
            raise Fail("rejected", "body must be a non-empty string")
        if len(body) > MAX_BODY:
            raise Fail(
                "rejected", f"body has {len(body)} characters; the limit is {MAX_BODY}"
            )
        created = self.run(
            "POST", f"repos/{self.space}/issues/{number}/comments", {"body": body}
        ).json()
        return {"ref": str(created["id"]), "url": created.get("html_url")}

    def list_since(self, data):
        number = self.channel(data)
        raw = data.get("cursor")
        cur = decode(raw)
        limit = max(1, min(PAGE, int(data.get("limit") or PAGE)))
        last_id = cur.get("id", 0)
        state, state_at = cur.get("state"), cur.get("state_at")
        age = now_epoch() - state_at if isinstance(state_at, (int, float)) else -1
        state_due = (
            data.get("fresh_state") is True
            or state not in ("open", "closed")
            or not 0 <= age < STATE_MAX_AGE
        )
        query = f"repos/{self.space}/issues/{number}/comments?per_page={PAGE}"
        since = f"&since={cur['since']}" if cur.get("since") else ""
        new, page, first_etag, first_full = [], 1, None, False
        while True:
            etag = (
                [f"If-None-Match: {cur['etag']}"]
                if page == 1 and cur.get("etag")
                else []
            )
            resp = self.run("GET", f"{query}&page={page}{since}", headers=etag)
            if resp.status == 304:
                if not state_due:
                    return {
                        "items": [],
                        "cursor": raw,
                        "more": False,
                        "channel_state": state,
                    }
                state, state_at = self.issue_state(number)
                return {
                    "items": [],
                    "cursor": encode(dict(cur, state=state, state_at=state_at)),
                    "more": False,
                    "channel_state": state,
                }
            batch = resp.json()
            if not isinstance(batch, list):
                raise Fail("unknown", "the comments list was not a list")
            if page == 1:
                first_etag, first_full = resp.headers.get("etag"), len(batch) >= PAGE
            new += [
                c
                for c in batch
                if isinstance(c, dict) and int(c.get("id", 0)) > last_id
            ]
            if len(new) > limit or len(batch) < PAGE:
                break
            page += 1
        more, new = len(new) > limit, new[:limit]
        if new or state_due:
            state, state_at = self.issue_state(number)
        reads = self.reactions(new)
        items = []
        for c in new:
            after = encode(
                {
                    "id": int(c["id"]),
                    "since": since_for(c.get("created_at")),
                    "etag": None,
                    "state": state,
                    "state_at": state_at,
                }
            )
            items.append(
                {
                    "ref": str(c["id"]),
                    "url": c.get("html_url"),
                    "created": c.get("created_at"),
                    "body": c.get("body") or "",
                    "reads": reads.get(int(c["id"]), []),
                    "after": after,
                }
            )
        if items:
            cursor = items[-1]["after"]
        else:  # nothing new: keep the place, remember the ETag so the next list is conditional
            cursor = encode(
                {
                    "id": last_id,
                    "since": cur.get("since"),
                    "etag": None if first_full else first_etag,
                    "state": state,
                    "state_at": state_at,
                }
            )
        return {"items": items, "cursor": cursor, "more": more, "channel_state": state}

    def issue_state(self, number):
        """("open" or "closed", when it was read) from GET issues/<n>."""
        issue = self.run("GET", f"repos/{self.space}/issues/{number}").json()
        return ("closed" if issue.get("state") == "closed" else "open"), int(
            now_epoch()
        )

    def reactions(self, comments):
        """{comment id: [{"mark", "at"}]} for the comments that carry reactions."""
        ids = [
            c["node_id"]
            for c in comments
            if c.get("node_id")
            and int((c.get("reactions") or {}).get("total_count") or 0) > 0
        ]
        found = {}
        for i in range(0, len(ids), PAGE):
            resp = self.run(
                "POST",
                "graphql",
                {"query": REACTIONS_QUERY, "variables": {"ids": ids[i : i + PAGE]}},
                read=True,
            )
            answer = resp.json()
            errors = answer.get("errors") if isinstance(answer, dict) else None
            if errors:
                if any(
                    isinstance(e, dict) and e.get("type") == "RATE_LIMITED"
                    for e in errors
                ):
                    raise Fail("rate_limited", "GitHub GraphQL rate limit", 60)
                raise Fail("unknown", f"GraphQL error: {str(errors[0])[:200]}")
            for node in (answer.get("data") or {}).get("nodes") or []:
                if not isinstance(node, dict) or "databaseId" not in node:
                    continue
                marks = []
                for r in (node.get("reactions") or {}).get("nodes") or []:
                    content = str(r.get("content", ""))
                    marks.append(
                        {
                            "mark": GRAPHQL_CONTENT.get(content, content.lower()),
                            "at": r.get("createdAt"),
                        }
                    )
                found[int(node["databaseId"])] = marks
        return found

    def mark_read(self, data):
        ref = self.channel(data, "ref")
        mark = data.get("mark")
        if mark not in REACTIONS:
            raise Fail(
                "rejected",
                f"{mark!r} is not a GitHub reaction ({', '.join(REACTIONS)})",
            )
        made = self.run(
            "POST",
            f"repos/{self.space}/issues/comments/{ref}/reactions",
            {"content": mark},
        ).json()
        at = made.get("created_at") or ""
        if not TIME_RE.match(at):
            at = datetime.fromtimestamp(now_epoch(), timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            )
        return {"ref": ref, "mark": mark, "at": at}

    def open_channel(self, data):
        label = str(data.get("label", ""))
        if not LABEL_RE.match(label):
            raise Fail("rejected", f"label {label!r} is not allowed")
        title, body = (
            str(data.get("title", ""))[:200],
            str(data.get("body", ""))[:MAX_BODY],
        )
        made = self.run(
            "POST",
            f"repos/{self.space}/issues",
            {"title": title, "body": body, "labels": [label]},
        ).json()
        return {"channel": str(made["number"])}

    def close_channel(self, data):
        number = self.channel(data)
        self.run("PATCH", f"repos/{self.space}/issues/{number}", {"state": "closed"})
        return {"channel": number, "state": "closed"}


def decode(raw):
    if raw is None:
        return {}
    try:
        cur = json.loads(raw)
    except (TypeError, ValueError):
        raise Fail("rejected", "the cursor is not one this adapter made")
    if not isinstance(cur, dict) or not isinstance(cur.get("id", 0), int):
        raise Fail("rejected", "the cursor is not one this adapter made")
    if cur.get("since") is not None and not TIME_RE.match(str(cur["since"])):
        raise Fail("rejected", "the cursor's time is malformed")
    return cur


def encode(cur):
    return json.dumps(cur, sort_keys=True, separators=(",", ":"))


def since_for(created):
    """The `since` for a cursor after a comment: 2 seconds before it was created, because GitHub
    may leave out comments updated exactly at `since`, and another comment can share its second.
    Comments already seen come back in that window and are dropped by id."""
    if not TIME_RE.match(str(created or "")):
        return None
    moment = datetime.strptime(created, "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=timezone.utc
    )
    return datetime.fromtimestamp(moment.timestamp() - 2, timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )


def main():
    op = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        try:
            data = json.loads(sys.stdin.read() or "{}")
        except ValueError:
            raise Fail("rejected", "the input was not JSON")
        if not isinstance(data, dict):
            raise Fail("rejected", "the input must be a JSON object")
        gh = GitHub(data)
        ops = {
            "send": gh.send,
            "list-since": gh.list_since,
            "mark-read": gh.mark_read,
            "open-channel": gh.open_channel,
            "close-channel": gh.close_channel,
        }
        if op not in ops:
            raise Fail("rejected", f"unknown operation {op!r}")
        print(json.dumps(ops[op](data)))
        return 0
    except Fail as f:
        print(
            json.dumps(
                {
                    "error": {
                        "kind": f.kind,
                        "message": f.message,
                        "retry_after": f.retry_after,
                    }
                }
            )
        )
        return 1
    except (KeyError, TypeError, ValueError) as exc:
        print(
            json.dumps(
                {
                    "error": {
                        "kind": "unknown",
                        "retry_after": None,
                        "message": f"unexpected answer from GitHub ({type(exc).__name__})",
                    }
                }
            )
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())
