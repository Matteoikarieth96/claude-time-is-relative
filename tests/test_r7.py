"""Round 7 (100 benchmark runs in blocks of 10): what changed to close the gap between the
estimate and the real time. Synthetic transcripts only."""
import importlib
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import REPO, T0, Transcript, remove_tmp  # noqa: E402

sys.path.insert(0, REPO)
task_eta = importlib.import_module("task_eta")

ELAPSED = "/usr/bin/python3 '/opt/task-eta/task_eta.py' elapsed"


def fake_task(model, effort, start, dur=60.0, proto_at=None, headless=False):
    return {"key": "k%f" % start, "start_ts": start, "dur_s": dur, "tools": 5, "proto": 1, "agents": 0,
            "interrupted": False, "model": model, "effort": effort, "proto_at": proto_at,
            "headless": headless, "call_marks": [0.0, dur - 5.0], "file": "/p/-work-acme/s.jsonl",
            "prompt": "Fix the login bug", "calls_by": {}}


class UnknownModelLines(unittest.TestCase):
    """With no reply yet (first prompt of a terminal or headless session) every model family with
    measured speeds gets its own lines, not only the ones the user picked lately."""

    def test_other_families_follow_the_ones_used_lately(self):
        work = [fake_task("opus-5-5", "xhigh", T0 + i) for i in range(30)]
        lat = {"opus-5-5|xhigh": (16.0, 4000), "sonnet-5-5|medium": (7.5, 600), "sonnet-5-5|high": (8.5, 800),
               "haiku-5-5|medium": (7.0, 500), "opus-5|high": (11.0, 40), "fable-5-1|high": (18.0, 1700)}
        combos = task_eta.main_combos(work, "medium", lat=lat)
        self.assertEqual([m for m, _ in combos], ["opus-5-5", "fable-5-1", "sonnet-5-5", "haiku-5-5"])
        self.assertTrue(all(e == "medium" for _, e in combos))
        # One version per family: the older Opus never takes a slot from another family.
        self.assertNotIn("opus-5", [m for m, _ in combos])

    def test_without_a_speed_table_it_is_the_old_behaviour(self):
        work = [fake_task("opus-5-5", "xhigh", T0 + i) for i in range(30)]
        self.assertEqual(task_eta.main_combos(work), [("opus-5-5", "xhigh")])


class ElapsedTail(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.projects = os.path.join(self.tmp.name, ".claude", "projects")

    def tearDown(self):
        remove_tmp(self.tmp)

    def test_the_parser_records_when_elapsed_ran(self):
        t = Transcript()
        t.prompt(T0, "Fix the login bug")
        t.tool(T0 + 5, "Edit", {"file_path": "/work/acme/app.py"}, T0 + 15)
        t.tool(T0 + 20, "Bash", {"command": "/usr/bin/python3 '/opt/task_eta.py' eta"}, T0 + 21)
        t.tool(T0 + 30, "Bash", {"command": ELAPSED}, T0 + 31)
        t.say(T0 + 42, "Done.", end=True)
        t.stop(T0 + 43)
        task = task_eta.parse_transcript(t.write(self.projects))[0]
        self.assertEqual(task["proto"], 2)
        self.assertEqual(task["proto_at"], 30.0)  # the elapsed call, not the eta one
        self.assertEqual(task["dur_s"] - task["proto_at"], 13.0)  # to the Stop, as dur_s

    def test_no_elapsed_call_no_mark(self):
        t = Transcript()
        t.task(T0, "Fix the login bug", steps=2)
        self.assertIsNone(task_eta.parse_transcript(t.write(self.projects))[0]["proto_at"])

    def test_bad_stored_values_are_dropped(self):
        for bad in ("12", True, float("nan"), [1]):
            task = fake_task("opus-5-5", "high", T0)
            task.update(key="k", start="x", proto_at=bad)
            self.assertNotIn("proto_at", task_eta.clean_task(task), bad)

    def test_tail_is_retimed_for_the_model(self):
        lat = {"opus-5-5|xhigh": (16.0, 4000), "sonnet-5-5|medium": (8.0, 600)}
        past = [fake_task("opus-5-5", "xhigh", T0 + i, dur=100.0, proto_at=80.0) for i in range(12)]
        now = {"model": "sonnet-5-5", "effort": "medium"}
        self.assertAlmostEqual(task_eta.reply_tail(past, now, lat), 10.0)   # 20 s on Opus xhigh, half on Sonnet
        self.assertAlmostEqual(task_eta.reply_tail(past, {"model": "opus-5-5", "effort": "xhigh"}, lat), 20.0)

    def test_too_few_marks_falls_back_to_the_last_call(self):
        past = [fake_task("opus-5-5", "xhigh", T0 + i, dur=100.0, proto_at=80.0 if i < 3 else None) for i in range(12)]
        self.assertAlmostEqual(task_eta.reply_tail(past, {"model": "opus-5-5", "effort": "xhigh"}, {}), 5.0)

    def test_tail_pool_matches_the_kind_of_session(self):
        app = [fake_task("opus-5-5", "xhigh", T0 + i, proto_at=40.0) for i in range(12)]
        bench = [fake_task("opus-5-5", "xhigh", T0 + 100 + i, proto_at=55.0, headless=True) for i in range(12)]
        for t in bench:
            t["file"] = "/p/-private-tmp-x-bench-runs-r7-a/s.jsonl"
        headless_pool = task_eta.tail_pool(app + bench, {"headless": True})
        self.assertTrue(all(t["headless"] for t in headless_pool))
        app_pool = task_eta.tail_pool(app + bench, {"headless": False})
        self.assertTrue(app_pool and not any(t["headless"] for t in app_pool))
        # Too few headless runs with a mark: the user's own tasks.
        few = task_eta.tail_pool(app + bench[:3], {"headless": True})
        self.assertTrue(few and not any(t["headless"] for t in few))


class SelfCalibratingRange(unittest.TestCase):
    def test_the_narrowest_range_that_held_half_the_time(self):
        qs = task_eta.RANGE_QS
        self.assertEqual(qs[0], 0.25)
        self.assertEqual(task_eta.pick_range_q(40, [24, 30, 33, 36]), 0)   # the quartiles held 60%
        self.assertEqual(task_eta.pick_range_q(40, [11, 15, 21, 25]), 2)   # 28%, 38%, then 52%
        self.assertEqual(task_eta.pick_range_q(40, [5, 8, 10, 12]), len(qs) - 1)  # none: the widest
        self.assertEqual(task_eta.pick_range_q(10, [1, 2, 3, 4]), 0)       # too few tested: quartiles


def agent_task(start, dur, sub_runs, model="opus-5-5", effort="xhigh"):
    t = fake_task(model, effort, start, dur=dur)
    t.update(agents=len(sub_runs), tools=8, sub={"agents": [{"prompt": "p", "dur_s": d} for d in sub_runs],
                                                 "busy_s": 0, "work_s": 0, "calls_by": {}})
    return t


class BriefSubagents(unittest.TestCase):
    """Tasks whose subagents each do a short job get their own line, "with brief subagents"."""

    def test_brief_is_the_median_subagent_run(self):
        self.assertIs(task_eta.agents_brief(agent_task(T0, 600, [60, 120, 900])), True)
        self.assertIs(task_eta.agents_brief(agent_task(T0, 3000, [700, 1500])), False)
        self.assertIsNone(task_eta.agents_brief(fake_task("opus-5-5", "xhigh", T0)))
        self.assertIsNone(task_eta.agents_brief(agent_task(T0, 600, ["60", True])))  # odd records ignored

    def lat(self):
        return {"opus-5-5|xhigh": (16.0, 4000)}

    def test_two_lines_once_both_halves_have_five_tasks(self):
        work = ([agent_task(T0 + i, 600 + i, [120, 180]) for i in range(5)]
                + [agent_task(T0 + 10 + i, 3000 + i, [1200, 1500]) for i in range(5)])
        pred = task_eta.Predictor(work, self.lat())
        short = task_eta.brief_estimate(pred, None, "opus-5-5", "xhigh")
        self.assertAlmostEqual(short[0], 602.0)
        ests = task_eta.kind_estimates(pred, None, "opus-5-5", "xhigh")
        self.assertAlmostEqual(ests["agents"][0], 3002.0)  # the "with subagents" line: the longer ones
        line = task_eta.kind_line("opus-5-5", "xhigh", "agents_brief", short)
        self.assertTrue(line.endswith("with brief subagents)"), line)
        minutes, _ = task_eta.parse_estimate(line)
        self.assertEqual(task_eta.KIND_RE.search(line[line.index("~"):]).group(1).lower(), "subagents")
        self.assertAlmostEqual(minutes, 10.0)

    def test_one_line_while_a_half_is_too_small(self):
        work = ([agent_task(T0 + i, 600 + i, [120]) for i in range(3)]
                + [agent_task(T0 + 10 + i, 3000 + i, [1200]) for i in range(6)])
        pred = task_eta.Predictor(work, self.lat())
        self.assertIsNone(task_eta.brief_estimate(pred, None, "opus-5-5", "xhigh"))
        all_agents = sorted(t["dur_s"] for t in work)
        self.assertAlmostEqual(task_eta.kind_estimates(pred, None, "opus-5-5", "xhigh")["agents"][0],
                               task_eta.pct(all_agents, 0.5))


if __name__ == "__main__":
    unittest.main()
