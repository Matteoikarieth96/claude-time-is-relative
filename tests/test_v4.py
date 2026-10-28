"""v4 (deep research of 2026-10-25): the task list's pace in eta, errors and compactions named and left out
of the calibration, fast mode timed apart, each model's own effort step. Synthetic data only."""
import importlib
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import REPO, T0, Transcript, iso, remove_tmp  # noqa: E402

sys.path.insert(0, REPO)
task_eta = importlib.import_module("task_eta")
PLAN = "mcp__ccd_turn__update_plan"


class Parsing(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.projects = os.path.join(self.tmp.name, ".claude", "projects")

    def tearDown(self):
        remove_tmp(self.tmp)

    def parse(self, t):
        return task_eta.parse_transcript(t.write(self.projects))

    def test_the_app_task_list(self):
        t = Transcript()
        t.prompt(T0, "Build the report")
        items = [{"content": "step %d" % i, "status": "pending"} for i in range(4)]
        t.tool(T0 + 2, PLAN, {"items": items}, T0 + 3)
        t.tool(T0 + 30, "Edit", {"file_path": "/work/acme/a.py"}, T0 + 40)
        t.tool(T0 + 41, PLAN, {"advance": True}, T0 + 42)
        t.tool(T0 + 60, PLAN, {"done": [2], "start": 3}, T0 + 61)
        t.say(T0 + 70, "Done.", end=True)
        t.stop(T0 + 71)
        task = self.parse(t)[0]
        self.assertEqual(task["plan_steps"], 4)
        self.assertEqual([m[1:] for m in task["plan_marks"]], [[0, 4], [1, 4], [2, 4]])
        self.assertEqual(task["plan_marks"][1][0], 41.0)  # seconds of task time

    def test_the_terminal_task_list(self):
        t = Transcript()
        t.prompt(T0, "Build the report")
        for i in range(3):
            t.tool(T0 + 2 + i, "TaskCreate", {"subject": "s%d" % i}, T0 + 2.5 + i)
        t.tool(T0 + 20, "TaskUpdate", {"taskId": "1", "status": "in_progress"}, T0 + 21)
        t.tool(T0 + 30, "TaskUpdate", {"taskId": "1", "status": "completed"}, T0 + 31)
        t.tool(T0 + 32, "TaskUpdate", {"taskId": "1", "status": "completed"}, T0 + 33)  # counted once
        t.say(T0 + 40, "Done.", end=True)
        t.stop(T0 + 41)
        task = self.parse(t)[0]
        self.assertEqual(task["plan_steps"], 3)
        self.assertEqual(task["plan_marks"][-1][1:], [1, 3])

    def test_errors_and_compactions_are_counted(self):
        t = Transcript()
        t.prompt(T0, "Fix the login bug")
        t.tool(T0 + 5, "Edit", {"file_path": "/work/acme/app.py"}, T0 + 15)
        t.records.append({"type": "system", "subtype": "api_error", "timestamp": iso(T0 + 20)})
        t.records.append({"type": "system", "subtype": "api_error", "timestamp": iso(T0 + 60)})
        t.records.append({"type": "system", "subtype": "compact_boundary", "timestamp": iso(T0 + 100)})
        t.say(T0 + 140, "Done.", end=True)
        t.stop(T0 + 141)
        task = self.parse(t)[0]
        self.assertEqual((task["api_errors"], task["compactions"]), (2, 1))
        self.assertAlmostEqual(task["err_lost_s"], 120.0)
        self.assertTrue(task_eta.disrupted(task))

    def test_fast_mode_is_timed_apart(self):
        t = Transcript()
        t.prompt(T0, "Fix the login bug")
        t.tool(T0 + 5, "Edit", {"file_path": "/work/acme/app.py"}, T0 + 15)
        t.records[-2]["message"]["usage"] = {"speed": "fast", "output_tokens": 50}
        t.say(T0 + 20, "Done.", end=True)
        t.stop(T0 + 21)
        task = self.parse(t)[0]
        self.assertIn("opus-5-5-fast|high", task["calls_by"])
        self.assertIn("opus-5-5|high", task["calls_by"])


def planned(i, dur, marks, kind_tools=8, steps=None):
    return {"key": "p%d" % i, "start_ts": T0 + i * 1000, "end_ts": T0 + i * 1000 + dur, "dur_s": dur,
            "tools": kind_tools, "proto": 0, "agents": 0, "big_writes": 0, "interrupted": False,
            "plan_marks": marks, "plan_steps": steps or (marks[0][2] if marks else 0)}


class PlanEta(unittest.TestCase):
    def test_the_pace_of_the_steps(self):
        # Past tasks whose steps all took the same time: the pace was right, factor 1.
        past = [planned(i, 400.0, [[0.0, 0, 4], [100.0, 1, 4], [200.0, 2, 4], [300.0, 3, 4]]) for i in range(12)]
        now = planned(99, 200.0, [[0.0, 0, 4], [100.0, 1, 4], [200.0, 2, 4]])
        left, low, high = task_eta.plan_eta(now, past)
        self.assertAlmostEqual(left, 200.0)
        self.assertEqual(task_eta.eta_for(now, past)[0], left)
        # Time already spent on the step in progress comes off.
        left2 = task_eta.plan_eta(dict(now, dur_s=250.0), past)[0]
        self.assertAlmostEqual(left2, 150.0)

    def test_no_pace_without_enough_history_or_with_subagents(self):
        past = [planned(i, 400.0, [[0.0, 0, 4], [200.0, 2, 4]]) for i in range(5)]
        now = planned(99, 200.0, [[0.0, 0, 4], [200.0, 2, 4]])
        self.assertIsNone(task_eta.plan_eta(now, past))
        many = past * 3
        self.assertIsNone(task_eta.plan_eta(dict(now, agents=2), many))
        self.assertIsNone(task_eta.plan_eta(planned(98, 50.0, [[0.0, 0, 2], [40.0, 1, 2]]), many))  # 2 steps

    def test_the_length_of_the_list_before_a_step_is_done(self):
        past = [planned(i, 60.0 * s, [[0.0, 0, s]], kind_tools=8) for i, s in enumerate([3, 4, 5, 6, 8] * 6)]
        now = dict(planned(99, 10.0, [[2.0, 0, 8]]), kind_declared="medium")
        left, low, high = task_eta.plan_size_eta(now, past)
        self.assertAlmostEqual(left, 470.0, delta=1)
        self.assertIsNone(task_eta.plan_size_eta(now, past[:20]))  # too few lists of this kind


class EffortStep(unittest.TestCase):
    def test_each_model_its_own_step(self):
        lat = {"opus-5-5|high": (15.0, 900), "opus-5-5|xhigh": (18.0, 900),
               "fable-5-1|high": (19.0, 900), "fable-5-1|max": (100.0, 40)}
        self.assertAlmostEqual(task_eta.step_factor(lat, "opus-5-5"), 1.2)
        secs, guessed = task_eta.call_latency(lat, "opus-5-5", "max")
        self.assertTrue(guessed)
        self.assertAlmostEqual(secs, 18.0 * 1.2)
        self.assertGreaterEqual(task_eta.step_factor(lat, "haiku-5-5"), 1.1)  # never measured: the average


class IndexFields(unittest.TestCase):
    def test_bad_new_fields_are_cleaned(self):
        base = {"key": "k", "start": "x", "start_ts": T0, "dur_s": 10.0, "tools": 2, "agents": 0}
        t = task_eta.clean_task(dict(base, plan_marks=[[1.0, 0, 4], ["x", 1, 4], [2.0, True, 4], [3.0, 1, 4]],
                                     plan_steps=-1, api_errors="2", err_lost_s=float("nan")))
        self.assertEqual(t["plan_marks"], [[1.0, 0, 4], [3.0, 1, 4]])
        self.assertEqual((t["plan_steps"], t["api_errors"], t["err_lost_s"]), (0, 0, 0.0))


class CallsDeclared(unittest.TestCase):
    """Experiment of 2026-10-25: Claude adds the tool calls it plans to its line."""

    def test_the_count_is_read_and_nothing_else_moves(self):
        line = "⏱ Estimated time with opus-5-5 xhigh: ~2 min (likely 1 to 4 min, medium, ~8 call)"
        self.assertEqual(task_eta.parse_calls(line), 8)
        self.assertEqual(task_eta.parse_estimate(line)[0], 2.0)
        self.assertEqual(task_eta.parse_kind(line), "medium")
        self.assertEqual(task_eta.parse_range(line), [60.0, 240.0])
        self.assertEqual(task_eta.parse_calls(line.replace("~8 call", "~12 tool calls")), 12)
        plain = "⏱ Estimated time with opus-5-5 xhigh: ~2 min (likely 1 to 4 min, medium)"
        self.assertEqual(task_eta.parse_calls(plain + "\n<!-- task-eta: ~9 call -->"), 9)  # the hidden comment
        self.assertEqual(task_eta.parse_calls("<!--task-eta:~14 calls-->"), 14)
        self.assertEqual(task_eta.parse_calls(plain + "\n\n[//]: # (task-eta: ~7 call)\n\nNext."), 7)  # what the app hides
        # Not on its own line: not a link definition (the app would show it); the visible-line form reads it.
        self.assertIsNone(task_eta.LINKREF_CALLS_RE.search(plain + " [//]: # (task-eta: ~7 call)"))
        self.assertIsNone(task_eta.parse_calls(plain + "\n<!-- some other comment: ~9 call -->"))
        for none in ("⏱ Estimated time with opus-5-5 xhigh: ~2 min (likely 1 to 4 min, medium)",
                     "⏱ Estimated time with opus-5-5 xhigh: ~2 min (likely 1 to 4 min, medium, ~0 call)",
                     "⏱ Estimated time with opus-5-5 xhigh: ~8 call", "no line here"):
            self.assertIsNone(task_eta.parse_calls(none), none)

    def test_the_parser_keeps_it(self):
        tmp = tempfile.TemporaryDirectory()
        try:
            t = Transcript()
            t.prompt(T0, "Fix the login bug")
            t.say(T0 + 2, "⏱ Estimated time with opus-5-5 high: ~2 min (likely 1 to 4 min, medium)\n\n[//]: # (task-eta: ~6 call)")
            t.tool(T0 + 5, "Edit", {"file_path": "/work/acme/app.py"}, T0 + 15)
            t.say(T0 + 20, "Done.", end=True)
            t.stop(T0 + 21)
            task = task_eta.parse_transcript(t.write(os.path.join(tmp.name, ".claude", "projects")))[0]
        finally:
            remove_tmp(tmp)
        self.assertEqual((task["calls_declared"], task["kind_declared"], task["est_range"]), (6, "medium", [60.0, 240.0]))
        base = {"key": "k", "start": "x", "start_ts": T0, "dur_s": 10.0, "tools": 2, "agents": 0}
        self.assertIsNone(task_eta.clean_task(dict(base, calls_declared="8"))["calls_declared"])
        self.assertEqual(task_eta.clean_task(dict(base, calls_declared=8))["calls_declared"], 8)


if __name__ == "__main__":
    unittest.main()
