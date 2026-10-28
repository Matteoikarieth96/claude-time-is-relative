"""The fixes of the adversarial review of 2026-10-25 (six reviewers, 885 real tasks). Synthetic
transcripts and tasks only."""
import importlib
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import REPO, T0, Transcript, iso, remove_tmp  # noqa: E402

sys.path.insert(0, REPO)
task_eta = importlib.import_module("task_eta")


def notification(t, ts, body):
    t.records.append({"type": "user", "timestamp": iso(ts), "origin": {"kind": "task-notification"},
                      "message": {"role": "user", "content": body}})


class Parsing(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.projects = os.path.join(self.tmp.name, ".claude", "projects")

    def tearDown(self):
        remove_tmp(self.tmp)

    def parse(self, t):
        return task_eta.parse_transcript(t.write(self.projects))

    def test_silence_before_the_first_reply_is_not_work(self):
        t = Transcript()
        t.prompt(T0, "Fix the login bug")
        # API errors and retries: Claude's first reply comes 30 minutes after the prompt.
        t.records.append({"type": "system", "subtype": "api_error", "timestamp": iso(T0 + 600)})
        t.tool(T0 + 1800, "Edit", {"file_path": "/work/acme/app.py"}, T0 + 1810)
        t.say(T0 + 1815, "Done.", end=True)
        t.stop(T0 + 1816)
        self.assertAlmostEqual(self.parse(t)[0]["dur_s"], 16, delta=1)

    def test_a_slow_first_reply_still_counts(self):
        t = Transcript()
        t.prompt(T0, "Fix the login bug")
        t.tool(T0 + 90, "Edit", {"file_path": "/work/acme/app.py"}, T0 + 100)
        t.say(T0 + 105, "Done.", end=True)
        t.stop(T0 + 106)
        self.assertAlmostEqual(self.parse(t)[0]["dur_s"], 106, delta=1)

    def test_work_on_an_earlier_tasks_report_counts_for_that_task(self):
        t = Transcript()
        t.prompt(T0, "Research three note apps")
        tid = t.tool(T0 + 2, "Agent", {"run_in_background": True, "description": "research"}, T0 + 3,
                     result="Async agent launched successfully. agentId: agent123abc")
        t.say(T0 + 5, "Started, I will report back.", end=True)
        t.stop(T0 + 6)
        t.prompt(T0 + 100, "Fix a typo in the readme")
        t.tool(T0 + 102, "Edit", {"file_path": "/work/acme/README.md"}, T0 + 105)
        t.say(T0 + 107, "Fixed.", end=True)
        t.stop(T0 + 108)
        notification(t, T0 + 400, "<task-notification><tool-use-id>%s</tool-use-id>"
                                  "<status>completed</status></task-notification>" % tid)
        # Claude handles the research report: two tool calls that are the research task's work.
        t.tool(T0 + 402, "Write", {"file_path": "/work/acme/notes.md", "content": "x"}, T0 + 404)
        t.tool(T0 + 405, "Bash", {"command": "ls"}, T0 + 406)
        t.say(T0 + 408, "The research is done: here it is.", end=True)
        t.stop(T0 + 410)
        first, second = self.parse(t)
        self.assertEqual(first["tools"], 3)
        self.assertEqual(second["tools"], 1)
        self.assertEqual(task_eta.task_kind(second), "quick")
        self.assertAlmostEqual(second["dur_s"], 8, delta=2)
        # Model time follows the calls: the typo task keeps only its own two.
        self.assertEqual(sum(c for c, _ in second["calls_by"].values()), 2)
        self.assertEqual(sum(c for c, _ in first["calls_by"].values()), 5)
        self.assertEqual(first["model_s"], round(sum(s for _, s in first["calls_by"].values()), 1))
        self.assertEqual(first["tool_names"].get("Bash"), 1)

    def test_a_command_the_harness_moved_to_the_background_belongs_to_its_task(self):
        t = Transcript()
        t.prompt(T0, "Run the slow build")
        t.tool(T0 + 2, "Bash", {"command": "make all"}, T0 + 125,
               result="Command did not complete within its 120s timeout and was moved to the background "
                      "(ID: b0qm2zjm1). Output is being written to: /tmp/b0qm2zjm1.output. You will be "
                      "notified when it completes.")
        t.say(T0 + 127, "The build runs in the background.", end=True)
        t.stop(T0 + 128)
        t.prompt(T0 + 200, "What is two plus two?")
        t.tool(T0 + 202, "Bash", {"command": "echo 4"}, T0 + 203)
        t.say(T0 + 205, "4.", end=True)
        t.stop(T0 + 206)
        # Twenty minutes later the build reports back: the wait is not the sum's.
        notification(t, T0 + 1400, "<task-notification><task-id>b0qm2zjm1</task-id>"
                                   "<status>completed</status></task-notification>")
        t.say(T0 + 1410, "The build finished fine.", end=True)
        t.stop(T0 + 1411)
        first, second = self.parse(t)
        self.assertLess(second["dur_s"], 30)


class PrintedRange(unittest.TestCase):
    def test_the_real_time_counts_as_printed(self):
        # Over 90 s the Actual line prints whole minutes, and the check follows it (user, 2026-10-28).
        self.assertTrue(task_eta.in_shown_range(60, 240, 240))
        self.assertTrue(task_eta.in_shown_range(60, 240, 269))    # prints "4 min": inside "1 to 4 min"
        self.assertFalse(task_eta.in_shown_range(60, 240, 271))   # prints "5 min"
        self.assertTrue(task_eta.in_shown_range(180, 1140, 160))  # "~3 min" against "3 to 19 min"
        self.assertFalse(task_eta.in_shown_range(180, 1140, 149)) # prints "2 min"
        # Under 90 s it prints seconds, so seconds count.
        self.assertFalse(task_eta.in_shown_range(60, 240, 59))
        self.assertTrue(task_eta.in_shown_range(30, 80, 80))
        self.assertTrue(task_eta.in_shown_range(30, 80, 80.4))    # prints "80 s"
        self.assertFalse(task_eta.in_shown_range(30, 80, 80.6))   # prints "81 s"
        self.assertTrue(task_eta.in_shown_range(23, 120, 85))     # "85 s" inside "23 s to 2 min"

    def test_bounds_match_the_printed_line(self):
        for lo in (3, 20, 44.6, 59, 61, 89, 150, 610, 1789):
            for hi in (lo + 0.5, lo * 1.5, lo * 3, lo * 9, 5000):
                printed = task_eta.parse_range("⏱ x: ~1 min (likely %s, quick)" % task_eta.fmt_range(lo, hi))
                self.assertEqual(list(task_eta.shown_bounds(lo, hi)), printed, (lo, hi))


def fake(i, dur, agents=0):
    start = T0 + i * 4000
    return {"key": "k%d" % i, "start": iso(start), "start_ts": start, "end_ts": start + dur, "dur_s": dur,
            "tools": 6 if agents else 2, "proto": 0, "agents": agents, "big_writes": 0, "interrupted": False,
            "monitor": False, "open": False, "model": "opus-5-5", "effort": "xhigh",
            "calls_by": {"opus-5-5|xhigh": [4, 60.0]}, "file": "/p/-work-acme/s.jsonl",
            "prompt": "task number %d" % i, "headless": False}


class RangeWidth(unittest.TestCase):
    def test_only_tasks_with_subagents_may_widen(self):
        spread = (0.4, 1.0, 2.5, 0.7, 1.6, 0.25, 1.2, 3.0, 0.9, 0.5)
        tasks = [fake(i, 40 * spread[i % 10]) for i in range(0, 80, 2)]
        tasks += [fake(i, 1800 * spread[i % 10], agents=2) for i in range(1, 80, 2)]
        idx = {"tasks": {t["key"]: t for t in tasks}}
        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch.object(task_eta, "PREDICTOR", os.path.join(tmp, "predictor.json")), \
                mock.patch.object(task_eta, "LABELS", os.path.join(tmp, "none.json")), \
                mock.patch.object(task_eta, "pick_range_q", return_value=3):
            corr = task_eta.calibrate(idx)
        # Every kind may widen (target 70% since 2026-10-25); with WIDEN_KINDS = agents only, quick kept the quartiles.
        self.assertEqual(corr["kinds"]["quick"]["q"], task_eta.RANGE_QS[3])
        self.assertEqual(corr["kinds"]["agents"]["q"], task_eta.RANGE_QS[3])
        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch.object(task_eta, "PREDICTOR", os.path.join(tmp, "predictor.json")), \
                mock.patch.object(task_eta, "LABELS", os.path.join(tmp, "none.json")), \
                mock.patch.object(task_eta, "WIDEN_KINDS", ("agents",)), \
                mock.patch.object(task_eta, "pick_range_q", return_value=3):
            self.assertEqual(task_eta.calibrate(idx)["kinds"]["quick"]["q"], 0.25)
        for kind in ("quick", "agents"):
            k = corr["kinds"][kind]
            self.assertTrue(0 <= k["early"] <= 1 - k["coverage"] + 1e-9, k)


if __name__ == "__main__":
    unittest.main()
