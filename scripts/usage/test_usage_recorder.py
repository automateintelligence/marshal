"""Tests for the usage recorder: statusline-sensor.sh, usage-courier.sh, usage-push.sh.
No network and no real clock: every run gets its time from USAGE_NOW, and the push tests use a
local bare repository named "origin" as the remote.
Run: python3 -I scripts/usage/test_usage_recorder.py
"""
import fcntl
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest

here = os.path.dirname(os.path.abspath(__file__))
SENSOR = os.path.join(here, "statusline-sensor.sh")
COURIER = os.path.join(here, "usage-courier.sh")
PUSH = os.path.join(here, "usage-push.sh")

# The fixtures were captured at 19:40 UTC. NOW is 20 minutes later (Tuesday afternoon, Pacific).
CAPTURED = "2026-10-27T19:40:00Z"
NOW = "2026-10-27T20:00:00Z"
AGE_90_MIN = "2026-10-27T21:10:00Z"
AGE_90_MIN_1_SEC = "2026-10-27T21:10:01Z"
AGE_91_MIN = "2026-10-27T21:11:00Z"
LATER = "2026-10-27T21:00:00Z"
EM_DASH = chr(0x2014)


def fixture(name):
    return os.path.join(here, "fixtures", name)


def read(path):
    with open(path) as fh:
        return fh.read()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


def sections(text):
    """Split usage.md into {'weekly': ..., 'five_hour': ...} using its two '## ' headings."""
    parts = re.split(r"^## ", text, flags=re.M)
    out = {}
    for part in parts[1:]:
        if part.startswith("Weekly"):
            out["weekly"] = part
        elif part.startswith("Five-hour"):
            out["five_hour"] = part
    return out


class SensorTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.out = os.path.join(self.tmp, "cache", "claude", "statusline.json")
        self.normal_input = json.loads(read(fixture("statusline-normal.json")))
        del self.normal_input["captured_at"]

    def tearDown(self):
        self._tmp.cleanup()

    def run_sensor(self, stdin, *args, now=NOW, out=None, **extra_env):
        env = dict(os.environ, USAGE_STATUSLINE_FILE=out or self.out, USAGE_NOW=now, **extra_env)
        return subprocess.run([SENSOR, *args], input=stdin, env=env,
                              capture_output=True, text=True, timeout=30)

    def test_saves_input_plus_captured_at(self):
        r = self.run_sensor(json.dumps(self.normal_input))
        self.assertEqual(r.returncode, 0)
        saved = json.loads(read(self.out))
        self.assertEqual(saved["captured_at"], NOW)
        del saved["captured_at"]
        self.assertEqual(saved, self.normal_input)

    def test_newer_reading_replaces_older_and_leaves_no_temp_file(self):
        self.run_sensor(json.dumps(self.normal_input), now=NOW)
        self.run_sensor(json.dumps(self.normal_input), now=LATER)
        self.assertEqual(json.loads(read(self.out))["captured_at"], LATER)
        self.assertEqual(os.listdir(os.path.dirname(self.out)), ["statusline.json"])

    def test_prints_an_empty_status_line_when_nothing_is_wrapped(self):
        r = self.run_sensor(json.dumps(self.normal_input))
        self.assertEqual(r.stdout.strip(), "")

    def test_wraps_an_existing_command_with_the_same_input(self):
        r = self.run_sensor(json.dumps(self.normal_input), fixture("wrapped-statusline.sh"))
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "WRAPPED Sonnet 5.5\n")
        self.assertEqual(json.loads(read(self.out))["captured_at"], NOW)

    def test_missing_wrapped_command_still_exits_zero_and_saves(self):
        r = self.run_sensor(json.dumps(self.normal_input), os.path.join(self.tmp, "nope.sh"))
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout.strip(), "")
        self.assertEqual(json.loads(read(self.out))["captured_at"], NOW)

    def test_failing_wrapped_command_still_exits_zero(self):
        bad = os.path.join(self.tmp, "bad.sh")
        write(bad, "cat >/dev/null; echo partial; exit 7\n")
        r = self.run_sensor(json.dumps(self.normal_input), bad)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(json.loads(read(self.out))["captured_at"], NOW)

    def test_malformed_json_exits_zero_and_keeps_the_last_good_file(self):
        self.run_sensor(json.dumps(self.normal_input), now=NOW)
        good = read(self.out)
        r = self.run_sensor(read(fixture("statusline-malformed.txt")), now=LATER)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stderr, "")
        self.assertEqual(read(self.out), good)
        self.assertEqual(os.listdir(os.path.dirname(self.out)), ["statusline.json"])

    def test_malformed_json_still_gets_the_wrapped_output(self):
        r = self.run_sensor(read(fixture("statusline-malformed.txt")), fixture("wrapped-statusline.sh"))
        self.assertEqual(r.returncode, 0)
        self.assertTrue(r.stdout.startswith("WRAPPED"))

    def test_empty_and_non_object_input_exit_zero_and_write_nothing(self):
        for text in ("", "   \n", "[1, 2]", "42", "null"):
            with self.subTest(stdin=text):
                r = self.run_sensor(text)
                self.assertEqual(r.returncode, 0)
                self.assertFalse(os.path.exists(self.out))

    def test_unwritable_location_exits_zero(self):
        r = self.run_sensor(json.dumps(self.normal_input), out="/dev/null/x/statusline.json")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stderr, "")

    def test_wrapped_command_gets_stdin_byte_for_byte(self):
        copy = os.path.join(self.tmp, "copy.json")
        wrapper = os.path.join(self.tmp, "copy.sh")
        write(wrapper, 'cat > "$SENSOR_TEST_COPY"\n')
        stdin = json.dumps(self.normal_input) + "\n\n"
        r = self.run_sensor(stdin, wrapper, SENSOR_TEST_COPY=copy)
        self.assertEqual(r.returncode, 0)
        with open(copy, "rb") as fh:
            self.assertEqual(fh.read(), stdin.encode())
        self.assertEqual(json.loads(read(self.out))["captured_at"], NOW)

    def test_wrapped_read_loop_sees_the_last_line(self):
        wrapper = os.path.join(self.tmp, "loop.sh")
        write(wrapper, "while IFS= read -r line; do\n"
                       "  printf 'GOT %s\\n' \"$(printf '%s' \"$line\" | jq -r .model.display_name)\"\n"
                       "done\n")
        r = self.run_sensor(json.dumps(self.normal_input) + "\n", wrapper)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "GOT Sonnet 5.5\n")

    def test_slow_wrapped_command_is_cut_off_and_its_early_output_kept(self):
        wrapper = os.path.join(self.tmp, "slow.sh")
        write(wrapper, "cat >/dev/null; printf early; sleep 20; echo late\n")
        start = time.monotonic()
        r = self.run_sensor(json.dumps(self.normal_input), wrapper, USAGE_STATUSLINE_TIMEOUT="0.5")
        elapsed = time.monotonic() - start
        self.assertEqual(r.returncode, 0)
        self.assertLess(elapsed, 5)
        self.assertEqual(r.stdout, "early")
        self.assertEqual(r.stderr, "")
        self.assertEqual(json.loads(read(self.out))["captured_at"], NOW)


class CourierTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.state = os.path.join(self.tmp, "state")
        self.statusline = os.path.join(self.tmp, "statusline.json")
        self.usage = os.path.join(self.state, "usage.md")
        self.log = os.path.join(self.state, "usage-log.md")

    def tearDown(self):
        self._tmp.cleanup()

    def courier(self, fixture_name=None, now=NOW, text=None):
        """Put a fixture (or literal text) in place as the statusline file, then run the courier."""
        if fixture_name is not None:
            shutil.copy(fixture(fixture_name), self.statusline)
        elif text is not None:
            write(self.statusline, text)
        env = dict(os.environ, USAGE_STATUSLINE_FILE=self.statusline, USAGE_STATE_DIR=self.state,
                   USAGE_NOW=now)
        r = subprocess.run([COURIER], env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        return read(self.usage)

    def log_lines(self):
        if not os.path.exists(self.log):
            return []
        return [ln for ln in read(self.log).splitlines() if ln.startswith("- ")]

    # Record contents

    def test_normal_reading(self):
        text = self.courier("statusline-normal.json")
        s = sections(text)
        self.assertIn("captured 2026-10-27T19:40:00Z", text)
        self.assertIn("20 minutes old", text)
        self.assertIn("State: ok", s["weekly"])
        self.assertIn("Used: 14%", s["weekly"])
        self.assertIn("Resets: Sun 2026-11-01 20:59 PST", s["weekly"])
        self.assertIn("1793595599", s["weekly"])
        self.assertIn("State: ok", s["five_hour"])
        self.assertIn("Used: 3%", s["five_hour"])
        self.assertIn("Resets: Tue 2026-10-27 15:19 PDT", s["five_hour"])
        self.assertIn("1793139599", s["five_hour"])

    def test_file_older_than_90_minutes_is_stale_and_shows_no_percent(self):
        text = self.courier("statusline-normal.json", now=AGE_91_MIN)
        s = sections(text)
        self.assertIn("State: stale", s["weekly"])
        self.assertIn("State: stale", s["five_hour"])
        self.assertIn("91 minutes old", text)
        self.assertIsNone(re.search(r"\d+(\.\d+)?%", text), text)
        self.assertNotIn("1793595599", text)

    def test_the_90_minute_line_is_inclusive(self):
        text = self.courier("statusline-normal.json", now=AGE_90_MIN)
        self.assertIn("Used: 14%", text)
        self.assertNotIn("stale", sections(text)["weekly"])
        text = self.courier("statusline-normal.json", now=AGE_90_MIN_1_SEC)
        self.assertIn("State: stale", sections(text)["weekly"])

    def test_old_age_is_written_in_hours(self):
        text = self.courier("statusline-normal.json", now="2026-10-27T23:05:00Z")
        self.assertIn("3 hours 25 minutes old", text)

    def test_missing_five_hour_window_is_absent_and_weekly_still_reads(self):
        s = sections(self.courier("statusline-no-five-hour.json"))
        self.assertIn("State: ok", s["weekly"])
        self.assertIn("Used: 14%", s["weekly"])
        self.assertIn("State: absent", s["five_hour"])
        self.assertNotIn("Used:", s["five_hour"])

    def test_resets_at_in_the_past_is_absent(self):
        s = sections(self.courier("statusline-week-reset-past.json"))
        self.assertIn("State: absent", s["weekly"])
        self.assertIn("already in the past", s["weekly"])
        self.assertNotIn("Used:", s["weekly"])
        self.assertIn("State: ok", s["five_hour"])

    def test_missing_statusline_file_is_stale(self):
        text = self.courier(now=NOW)
        self.assertIn("State: stale", sections(text)["weekly"])
        self.assertIn("no statusline file", text)

    def test_malformed_statusline_file_is_stale(self):
        text = self.courier(text=read(fixture("statusline-malformed.txt")))
        self.assertIn("State: stale", sections(text)["weekly"])
        self.assertIn("could not be read", text)

    def test_record_is_rewritten_each_run_not_appended(self):
        self.courier("statusline-normal.json", now=NOW)
        text = self.courier("statusline-normal.json", now=LATER)
        self.assertEqual(text.count("## Weekly"), 1)
        self.assertEqual(text.count("## Five-hour"), 1)
        self.assertIn("2026-10-27T21:00:00Z", text)

    def test_times_are_shown_in_pacific_with_the_utc_time_alongside_the_written_time(self):
        text = self.courier("statusline-normal.json")
        self.assertIn("2026-10-27T20:00:00Z (2026-10-27 13:00 PDT)", text)

    def test_no_em_dashes_in_any_output(self):
        for name in ("statusline-normal.json", "statusline-no-five-hour.json",
                     "statusline-week-reset-past.json"):
            self.courier(name)
        self.courier("statusline-normal.json", now=AGE_91_MIN)
        self.assertNotIn(EM_DASH, read(self.usage))
        self.assertNotIn(EM_DASH, read(self.log))

    # Log rule

    def test_first_reading_is_logged(self):
        self.courier("statusline-normal.json")
        lines = self.log_lines()
        self.assertEqual(len(lines), 1)
        self.assertIn("2026-10-27T20:00:00Z", lines[0])
        self.assertIn("week 14%", lines[0])
        self.assertIn("5-hour 3%", lines[0])

    def test_unchanged_percent_adds_no_log_line(self):
        self.courier("statusline-normal.json", now=NOW)
        self.courier("statusline-normal.json", now=LATER)
        self.assertEqual(len(self.log_lines()), 1)

    def test_change_under_one_point_adds_no_log_line(self):
        self.courier("statusline-normal.json")
        self.courier("statusline-week-14-9.json", now=LATER)
        self.assertEqual(len(self.log_lines()), 1)

    def test_change_of_one_point_is_measured_from_the_last_logged_line(self):
        self.courier("statusline-normal.json")
        self.courier("statusline-week-14-9.json", now="2026-10-27T20:30:00Z")
        self.assertEqual(len(self.log_lines()), 1)
        self.courier("statusline-week-15.json", now=LATER)
        lines = self.log_lines()
        self.assertEqual(len(lines), 2)
        self.assertIn("week 15%", lines[1])

    def test_five_hour_percent_alone_adds_no_log_line(self):
        self.courier("statusline-normal.json")
        self.courier("statusline-five-hour-9.json", now=LATER)
        self.assertEqual(len(self.log_lines()), 1)

    def test_going_stale_is_logged_once_and_recovery_is_logged(self):
        self.courier("statusline-normal.json", now=NOW)
        self.courier("statusline-normal.json", now="2026-10-27T22:00:00Z")
        lines = self.log_lines()
        self.assertEqual(len(lines), 2)
        self.assertIn("week stale", lines[1])
        self.assertIn("5-hour stale", lines[1])
        self.courier("statusline-normal.json", now="2026-10-27T23:00:00Z")
        self.assertEqual(len(self.log_lines()), 2)
        fresh = json.loads(read(fixture("statusline-normal.json")))
        fresh["captured_at"] = "2026-10-27T23:50:00Z"
        fresh["rate_limits"]["five_hour"]["resets_at"] = 1793160000
        self.courier(text=json.dumps(fresh), now="2026-10-28T00:00:00Z")
        lines = self.log_lines()
        self.assertEqual(len(lines), 3)
        self.assertIn("week 14%", lines[2])

    def test_a_window_becoming_absent_is_logged(self):
        self.courier("statusline-normal.json")
        self.courier("statusline-no-five-hour.json", now=LATER)
        lines = self.log_lines()
        self.assertEqual(len(lines), 2)
        self.assertIn("5-hour absent", lines[1])
        self.assertIn("week 14%", lines[1])

    def test_weekly_window_past_its_reset_is_logged_as_absent(self):
        self.courier("statusline-normal.json", now=NOW)
        self.courier("statusline-week-reset-past.json", now=LATER)
        lines = self.log_lines()
        self.assertEqual(len(lines), 2)
        self.assertIn("week absent", lines[1])
        self.assertIn("5-hour 3%", lines[1])

    def test_capture_time_more_than_5_minutes_in_the_future_is_stale(self):
        # Captured 19:40, the clock says 19:30: ten minutes in the future.
        text = self.courier("statusline-normal.json", now="2026-10-27T19:30:00Z")
        s = sections(text)
        self.assertIn("State: stale", s["weekly"])
        self.assertIn("State: stale", s["five_hour"])
        self.assertIn("in the future", text)
        self.assertIn("clock changed?", text)
        self.assertIsNone(re.search(r"\d+(\.\d+)?%", text), text)
        self.assertNotIn("1793595599", text)
        self.assertIn("week stale", self.log_lines()[-1])

    def test_capture_time_up_to_5_minutes_in_the_future_is_clock_skew_and_ok(self):
        for now in ("2026-10-27T19:35:00Z", "2026-10-27T19:38:00Z"):
            with self.subTest(now=now):
                text = self.courier("statusline-normal.json", now=now)
                self.assertIn("State: ok", sections(text)["weekly"])
                self.assertIn("Used: 14%", text)
                self.assertIn("0 minutes old", text)
        text = self.courier("statusline-normal.json", now="2026-10-27T19:34:59Z")
        self.assertIn("State: stale", sections(text)["weekly"])

    def test_log_has_an_explanatory_header_written_once(self):
        self.courier("statusline-normal.json", now=NOW)
        self.courier("statusline-week-15.json", now=LATER)
        text = read(self.log)
        self.assertTrue(text.startswith("# Usage log"))
        self.assertEqual(text.count("# Usage log"), 1)


class PushTests(unittest.TestCase):
    """Runs usage-push.sh in a throwaway repository whose remote 'origin' is a local bare repo."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.remote = os.path.join(self.tmp, "remote.git")
        self.work = os.path.join(self.tmp, "work")
        self.env = dict(
            os.environ, HOME=self.tmp, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1",
            GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test" "@test.invalid",
            GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test" "@test.invalid",
            USAGE_STATUSLINE_FILE=os.path.join(self.tmp, "statusline.json"), USAGE_NOW=NOW,
        )
        self.git(self.tmp, "init", "-q", "--bare", "-b", "main", self.remote)
        self.git(self.tmp, "init", "-q", "-b", "main", self.work)
        os.makedirs(os.path.join(self.work, "scripts", "usage"))
        os.makedirs(os.path.join(self.work, "state"))
        for script in (COURIER, PUSH):
            shutil.copy(script, os.path.join(self.work, "scripts", "usage"))
        write(os.path.join(self.work, "state", "budget.md"), "# Budget\n")
        self.git(self.work, "add", ".")
        self.git(self.work, "commit", "-q", "-m", "initial")
        self.git(self.work, "remote", "add", "origin", self.remote)
        self.git(self.work, "push", "-q", "origin", "main")
        shutil.copy(fixture("statusline-normal.json"), self.env["USAGE_STATUSLINE_FILE"])

    def tearDown(self):
        self._tmp.cleanup()

    def git(self, cwd, *args, check=True):
        r = subprocess.run(["git", *args], cwd=cwd, env=self.env, capture_output=True,
                           text=True, timeout=30)
        if check:
            self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.strip()

    def push(self, now=NOW, **extra_env):
        env = dict(self.env, USAGE_NOW=now, **extra_env)
        return subprocess.run([os.path.join(self.work, "scripts", "usage", "usage-push.sh")],
                              cwd=self.work, env=env, capture_output=True, text=True, timeout=60)

    def remote_head(self):
        return self.git(self.remote, "rev-parse", "main")

    def test_commits_and_pushes_only_the_two_state_files(self):
        write(os.path.join(self.work, "state", "scratch.md"), "someone else's file\n")
        before = self.remote_head()
        r = self.push()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotEqual(self.remote_head(), before)
        self.assertEqual(self.remote_head(), self.git(self.work, "rev-parse", "HEAD"))
        files = self.git(self.remote, "show", "--name-only", "--format=", "main").split("\n")
        self.assertEqual(sorted(files), ["state/usage-log.md", "state/usage.md"])
        self.assertIn("?? state/scratch.md", self.git(self.work, "status", "--porcelain"))

    def test_identical_second_run_adds_no_commit(self):
        self.assertEqual(self.push().returncode, 0)
        head = self.remote_head()
        r = self.push()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.remote_head(), head)

    def test_failed_push_exits_nonzero_and_the_next_run_pushes_everything(self):
        hook = os.path.join(self.remote, "hooks", "pre-receive")
        write(hook, "#!/bin/sh\necho 'rejected for the test' >&2\nexit 1\n")
        os.chmod(hook, 0o755)
        before = self.remote_head()
        r = self.push(now=NOW)
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.remote_head(), before)
        os.remove(hook)
        r = self.push(now=LATER)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.remote_head(), self.git(self.work, "rev-parse", "HEAD"))
        self.assertEqual(self.git(self.remote, "rev-list", "--count", f"{before}..main"), "2")

    def test_pulls_with_rebase_before_pushing(self):
        other = os.path.join(self.tmp, "other")
        self.git(self.tmp, "clone", "-q", self.remote, other)
        write(os.path.join(other, "state", "watch.md"), "new from someone else\n")
        self.git(other, "add", "state/watch.md")
        self.git(other, "commit", "-q", "-m", "other work")
        self.git(other, "push", "-q", "origin", "main")
        r = self.push()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.remote_head(), self.git(self.work, "rev-parse", "HEAD"))
        self.assertTrue(os.path.exists(os.path.join(self.work, "state", "watch.md")))
        self.assertEqual(self.git(self.work, "rev-list", "--merges", "--count", "HEAD"), "0")

    def test_refuses_to_run_on_a_branch_other_than_main(self):
        self.git(self.work, "checkout", "-q", "-b", "feature")
        head, before = self.git(self.work, "rev-parse", "HEAD"), self.remote_head()
        r = self.push()
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.git(self.work, "rev-parse", "HEAD"), head)
        self.assertEqual(self.remote_head(), before)

    def test_unreachable_remote_exits_nonzero_and_writes_nothing(self):
        self.git(self.work, "remote", "set-url", "origin", os.path.join(self.tmp, "gone.git"))
        r = self.push()
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(self.work, "state", "usage.md")))

    def test_push_script_never_forces(self):
        text = read(PUSH)
        self.assertNotIn("--force", text)
        self.assertNotIn("--mirror", text)
        self.assertIsNone(re.search(r"git push[^\n]*\s-[a-zA-Z]*f", text))

    def fake_git(self, on_pull="", on_push=""):
        """A git on PATH that runs on_pull or on_push (shell text) before passing the command to
        the real git, and passes every other command straight through. Returns the new PATH."""
        bindir = os.path.join(self.tmp, "fakebin")
        real = shutil.which("git", path=self.env["PATH"])
        write(os.path.join(bindir, "git"),
              "#!/bin/sh\n"
              'case " $* " in\n'
              f'  *" pull "*) {on_pull or ":"} ;;\n'
              f'  *" push "*) {on_push or ":"} ;;\n'
              "esac\n"
              f'exec "{real}" "$@"\n')
        os.chmod(os.path.join(bindir, "git"), 0o755)
        return bindir + os.pathsep + self.env["PATH"]

    def stubborn_pull(self, quiet):
        """PATH whose git pull starts a child that ignores SIGTERM and sleeps 30 seconds, then
        waits for it (like a credential helper or ssh that hangs). With quiet, the child does not
        hold the run's output open. The child's pid is killed when the test ends."""
        pidfile = os.path.join(self.tmp, "stubborn.pid")
        redirect = " >/dev/null 2>&1" if quiet else ""
        child = f"trap '' TERM; echo \\$\\$ > {pidfile}; exec sleep 30{redirect}"
        path = self.fake_git(on_pull=f'sh -c "{child}" & wait; exit 1')

        def kill_child():
            try:
                os.kill(int(read(pidfile)), 9)
            except (OSError, ValueError):
                pass
        self.addCleanup(kill_child)
        return path, pidfile

    @staticmethod
    def alive(pid):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        stat = read(f"/proc/{pid}/stat")
        return stat.rsplit(")", 1)[1].split()[0] != "Z"

    def test_a_timed_out_pull_kills_children_that_ignore_term(self):
        path, pidfile = self.stubborn_pull(quiet=False)
        start = time.monotonic()
        r = self.push(PATH=path, USAGE_PUSH_TIMEOUT="1")
        self.assertLess(time.monotonic() - start, 10)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("timed out", r.stderr)
        self.assertFalse(self.alive(int(read(pidfile))))
        self.assertFalse(os.path.exists(self.usage_md()))

    def test_a_child_left_by_a_timed_out_pull_does_not_keep_the_lock(self):
        path, _ = self.stubborn_pull(quiet=True)
        before = self.remote_head()
        r = self.push(PATH=path, USAGE_PUSH_TIMEOUT="1")
        self.assertNotEqual(r.returncode, 0)
        r = self.push(now=LATER)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("holds the lock", r.stdout + r.stderr)
        self.assertNotEqual(self.remote_head(), before)
        self.assertEqual(self.remote_head(), self.git(self.work, "rev-parse", "HEAD"))

    def test_a_push_overtaken_by_another_commit_fails_and_loses_nothing(self):
        # Between the run's pull and its push, another clone pushes a commit, so the run's push is
        # not a fast-forward. The run must fail rather than overwrite it, and the next run recovers.
        other = os.path.join(self.tmp, "other")
        self.git(self.tmp, "clone", "-q", self.remote, other)
        write(os.path.join(other, "state", "watch.md"), "pushed while the run was busy\n")
        self.git(other, "add", "state/watch.md")
        self.git(other, "commit", "-q", "-m", "other work")
        other_head = self.git(other, "rev-parse", "HEAD")
        real = shutil.which("git", path=self.env["PATH"])
        path = self.fake_git(on_push=f'"{real}" -C "{other}" push -q origin main')
        r = self.push(PATH=path)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("push", r.stderr)
        self.assertEqual(self.remote_head(), other_head)
        self.assertNotEqual(self.git(self.work, "rev-parse", "HEAD"), other_head)
        r = self.push(now=LATER)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.remote_head(), self.git(self.work, "rev-parse", "HEAD"))
        self.git(self.remote, "merge-base", "--is-ancestor", other_head, "main")
        self.assertIn("pushed while the run was busy",
                      self.git(self.remote, "show", "main:state/watch.md"))
        self.assertIn("2026-10-27T21:00:00Z", self.git(self.remote, "show", "main:state/usage.md"))
        self.assertEqual(self.git(self.remote, "rev-list", "--merges", "--count", "main"), "0")

    def usage_md(self):
        return os.path.join(self.work, "state", "usage.md")

    def hang_helper(self):
        """A git remote helper for URLs like hang::x that never answers. Returns a PATH using it."""
        bindir = os.path.join(self.tmp, "bin")
        write(os.path.join(bindir, "git-remote-hang"), "#!/bin/sh\nsleep 20\n")
        os.chmod(os.path.join(bindir, "git-remote-hang"), 0o755)
        return bindir + os.pathsep + self.env["PATH"]

    def test_a_run_that_finds_the_lock_taken_exits_zero_and_does_nothing(self):
        lock = os.path.join(self.work, self.git(self.work, "rev-parse", "--git-path",
                                                "usage-push.lock"))
        before = self.remote_head()
        with open(lock, "w") as fh:
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
            r = self.push()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len((r.stdout + r.stderr).strip().splitlines()), 1)
        self.assertEqual(self.remote_head(), before)
        self.assertFalse(os.path.exists(self.usage_md()))
        r = self.push()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotEqual(self.remote_head(), before)

    def test_a_rejected_commit_is_cleaned_up_and_the_next_run_pushes(self):
        hook = os.path.join(self.work, ".git", "hooks", "pre-commit")
        write(hook, "#!/bin/sh\necho 'rejected for the test' >&2\nexit 1\n")
        os.chmod(hook, 0o755)
        before = self.remote_head()
        r = self.push(now=NOW)
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.remote_head(), before)
        os.remove(hook)
        r = self.push(now=LATER)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.remote_head(), self.git(self.work, "rev-parse", "HEAD"))
        self.assertEqual(self.git(self.work, "status", "--porcelain", "--untracked-files=no"), "")
        self.assertIn("2026-10-27T21:00:00Z", self.git(self.remote, "show", "main:state/usage.md"))

    def test_another_modified_tracked_file_still_stops_the_run_and_is_kept(self):
        budget = os.path.join(self.work, "state", "budget.md")
        write(budget, "# Budget\nlocal edit\n")
        before = self.remote_head()
        r = self.push()
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.remote_head(), before)
        self.assertEqual(read(budget), "# Budget\nlocal edit\n")

    def test_a_hung_pull_times_out_and_exits_nonzero(self):
        self.git(self.work, "remote", "set-url", "origin", "hang::x")
        start = time.monotonic()
        r = self.push(PATH=self.hang_helper(), USAGE_PUSH_TIMEOUT="1")
        self.assertLess(time.monotonic() - start, 10)
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(os.path.exists(self.usage_md()))
        self.assertFalse(os.path.exists(os.path.join(self.work, ".git", "rebase-merge")))
        self.assertFalse(os.path.exists(os.path.join(self.work, ".git", "rebase-apply")))

    def test_a_hung_push_times_out_and_the_next_run_pushes(self):
        self.git(self.work, "remote", "set-url", "--push", "origin", "hang::x")
        before = self.remote_head()
        start = time.monotonic()
        r = self.push(PATH=self.hang_helper(), USAGE_PUSH_TIMEOUT="1")
        self.assertLess(time.monotonic() - start, 10)
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.remote_head(), before)
        self.git(self.work, "remote", "set-url", "--push", "origin", self.remote)
        r = self.push(now=LATER)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.remote_head(), self.git(self.work, "rev-parse", "HEAD"))

    def test_an_ssh_remote_runs_ssh_in_batch_mode(self):
        calls = os.path.join(self.tmp, "ssh-calls.txt")
        fake = os.path.join(self.tmp, "fake-ssh")
        write(fake, f'#!/bin/sh\necho "$@" >> {calls}\nexit 255\n')
        os.chmod(fake, 0o755)
        self.git(self.work, "remote", "set-url", "origin", "git" "@example.invalid:repo.git")
        r = self.push(GIT_SSH_COMMAND=fake, USAGE_PUSH_TIMEOUT="5")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("-o BatchMode=yes", read(calls))


if __name__ == "__main__":
    unittest.main()
