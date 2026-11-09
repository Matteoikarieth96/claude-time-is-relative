"""v5 (review 2026-11-09): plan approvals and offer cards are waits for the user; the report shows the
width of the ranges and the miss of the ~ value next to the share held, and warns when a kind already
has the widest range."""
import importlib
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import REPO, T0, Transcript, remove_tmp, run  # noqa: E402

sys.path.insert(0, REPO)
task_eta = importlib.import_module("task_eta")

OFFER = "mcp__ccd_session__start_session"


class Waits(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.projects = os.path.join(self.tmp.name, ".claude", "projects")

    def tearDown(self):
        remove_tmp(self.tmp)

    def test_which_tools_wait(self):
        self.assertEqual(task_eta.waits_for_user("AskUserQuestion", {}), "question")
        self.assertEqual(task_eta.waits_for_user("ExitPlanMode", {"plan": "x"}), "plan")
        self.assertEqual(task_eta.waits_for_user(OFFER, {"initiation": "offer", "title": "x"}), "choice")
        self.assertIsNone(task_eta.waits_for_user(OFFER, {"initiation": "own_initiative"}))
        self.assertIsNone(task_eta.waits_for_user(OFFER, {"initiation": "user_asked"}))
        self.assertIsNone(task_eta.waits_for_user(OFFER, None))
        self.assertIsNone(task_eta.waits_for_user("Bash", {"command": "ls"}))

    def parse(self, name, tool_input):
        t = Transcript()
        t.prompt(T0, "Plan the release")
        t.tool(T0 + 5, name, tool_input, T0 + 605)  # the user answers 10 min later
        t.say(T0 + 615, "Done.", end=True)
        t.stop(T0 + 616)
        return task_eta.parse_transcript(t.write(self.projects))[0]

    def test_plan_approval_is_not_counted(self):
        task = self.parse("ExitPlanMode", {"plan": "1. do it"})
        self.assertAlmostEqual(task["dur_s"], 16, delta=1)
        self.assertAlmostEqual(task["wait_s"], 600, delta=1)

    def test_offer_card_is_not_counted(self):
        task = self.parse(OFFER, {"initiation": "offer", "title": "Fix the docs"})
        self.assertAlmostEqual(task["dur_s"], 16, delta=1)
        self.assertAlmostEqual(task["wait_s"], 600, delta=1)

    def test_a_session_started_at_once_is_work(self):
        # "own_initiative" and "user_asked" return at once in real use; here the result is late on
        # purpose, to show the time is not taken out.
        task = self.parse(OFFER, {"initiation": "own_initiative", "title": "Fix the docs"})
        self.assertAlmostEqual(task["dur_s"], 616, delta=1)
        self.assertAlmostEqual(task.get("wait_s") or 0, 0, delta=1)

    def test_parser_version_bumped(self):
        self.assertGreaterEqual(task_eta.PARSER_VERSION, 15)


def line(start, dur_s, lo, hi, est_min):
    return {"start_ts": start, "dur_s": dur_s, "est_range": [lo, hi], "estimate_min": est_min}


class ReportNumbers(unittest.TestCase):
    def test_range_width_is_the_median_ratio(self):
        lines = [line(T0, 60, 60, 240, 2), line(T0, 60, 30, 60, 1), line(T0, 60, 60, 360, 3)]
        self.assertAlmostEqual(task_eta.range_width(lines), 4.0)
        self.assertIsNone(task_eta.range_width([]))
        self.assertIsNone(task_eta.range_width([line(T0, 60, 0, 60, 1)]))  # no ratio from a zero low

    def test_point_miss_is_symmetric(self):
        # 2x above, 2x below, exact: the median miss is 2x.
        lines = [line(T0, 240, 60, 600, 2), line(T0, 60, 30, 600, 2), line(T0, 120, 60, 600, 2)]
        self.assertAlmostEqual(task_eta.point_miss(lines), 2.0)
        self.assertIsNone(task_eta.point_miss([dict(line(T0, 60, 30, 90, 1), estimate_min=None)]))

    def test_by_week_starts_on_monday(self):
        monday = task_eta.datetime(2026, 11, 2, 12).timestamp()
        tasks = [{"start_ts": monday + d * 86400} for d in (0, 6, 7, 8)]
        weeks = task_eta.by_week(tasks)
        self.assertEqual([(m.day, len(g)) for m, g in weeks], [(2, 2), (9, 2)])
        self.assertEqual(len(task_eta.by_week(tasks, weeks=1)), 1)

    def test_widest_kinds(self):
        corr = {"kinds": {"quick": {"q": 0.1}, "medium": {"q": 0.15}, "long": {"q": 0.1}, "agents": {"q": None}}}
        self.assertEqual(task_eta.widest_kinds(corr), ["quick", "long"])
        self.assertEqual(task_eta.widest_kinds(None), [])


class Report(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        projects = os.path.join(self.home, ".claude", "projects")
        start = T0
        for i in range(8):
            t = Transcript(session="s%d" % i)
            est = "⏱ Estimated time with opus-5-5 high: ~1 min (likely 30 s to 2 min, medium)"
            start = t.task(start + 3 * 86400, "Fix bug number %d" % i, steps=5, step_s=12 + i, estimate=est)
            t.write(projects)

    def tearDown(self):
        remove_tmp(self.tmp)

    def test_report_shows_width_and_miss_by_week(self):
        res = run(["report"], self.home)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("Ranges as printed, by week", res.stdout)
        self.assertIn("the target is at least 7 in 10", res.stdout)
        self.assertNotIn("the target is 50%", res.stdout)
        rows = [l for l in res.stdout.splitlines() if l.startswith("  ") and l.rstrip().endswith("x")]
        self.assertTrue(any(l.lstrip().startswith("since ") for l in rows), res.stdout)
        self.assertTrue(all(" 4.0x " in l for l in rows), rows)  # 30 s to 2 min
        since = next(l for l in rows if l.lstrip().startswith("since "))
        self.assertIn("    8 ", since)


if __name__ == "__main__":
    unittest.main()
