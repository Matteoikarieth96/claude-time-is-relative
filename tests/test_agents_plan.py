"""The planned-subagents part of the hidden line (experiment, since 2026-10-28):
"[//]: # (task-eta: ~8 call, 3 agents, 1 long)"."""
import importlib
import os
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import REPO, T0, Transcript, remove_tmp  # noqa: E402

sys.path.insert(0, REPO)
task_eta = importlib.import_module("task_eta")

LINE = "⏱ Estimated time with opus-5-5 high: ~35 min (likely 20 to 90 min, with subagents)\n\n"


class ParsePlan(unittest.TestCase):
    def test_the_full_line(self):
        for text, want in (("[//]: # (task-eta: ~18 call, 3 agents, 1 long)", (18, 3, 1)),
                           ("[//]: # (task-eta: ~4 call, 0 agents, 0 long)", (4, 0, 0)),
                           ("[//]: # (task-eta: ~9 calls, 1 agent, 0 long)", (9, 1, 0)),
                           ("[//]: # (task-eta: ~9 call,5 subagents,2 long)", (9, 5, 2)),
                           ("[//]: # (task-eta: ~9 call, 4 sub agents)", (9, 4, None)),
                           ("[//]: # (task-eta: ~9 chiamate, 2 agenti, 1 lunghi)", (9, 2, 1)),
                           ("<!-- task-eta: ~6 call, 2 agents, 2 long -->", (6, 2, 2))):
            self.assertEqual(task_eta.parse_plan(LINE + text + "\n\nNext."), want, text)

    def test_the_older_forms_still_read(self):
        self.assertEqual(task_eta.parse_plan(LINE + "[//]: # (task-eta: ~7 call)\n"), (7, None, None))
        self.assertEqual(task_eta.parse_calls(LINE + "[//]: # (task-eta: ~7 call, 2 agents, 1 long)\n"), 7)
        visible = "⏱ Estimated time with opus-5-5 high: ~2 min (likely 1 to 4 min, medium, ~8 call)"
        self.assertEqual(task_eta.parse_plan(visible), (8, None, None))

    def test_bad_values_are_dropped(self):
        # more long than planned, or an absurd count: kept out, the call count still read
        self.assertEqual(task_eta.parse_plan(LINE + "[//]: # (task-eta: ~9 call, 1 agents, 3 long)\n"), (9, 1, None))
        self.assertEqual(task_eta.parse_plan(LINE + "[//]: # (task-eta: ~9 call, 500 agents, 3 long)\n"), (9, None, None))
        # long without agents is not the format: the line does not match at all
        self.assertEqual(task_eta.parse_plan(LINE + "[//]: # (task-eta: ~9 call, 3 long)\n"), (None, None, None))

    def test_linear_on_a_run_of_spaces(self):
        n = 40000
        for rx, text in ((task_eta.LINKREF_CALLS_RE, "[//]: # (task-eta: ~7 call," + " " * n + "x"),
                         (task_eta.LINKREF_CALLS_RE, "[//]: # (task-eta: ~7 call, 3" + " \t" * n + "x)"),
                         (task_eta.LINKREF_CALLS_RE, "[//]: # (task-eta: ~7 call, 3 agents" + " " * n + "x)"),
                         (task_eta.LINKREF_CALLS_RE, "[//]: # (task-eta: ~7 call, 3 agents, 1" + " " * n + "x)"),
                         (task_eta.HIDDEN_CALLS_RE, "<!-- task-eta: ~7 call, 3 agents" + " " * n + "x")):
            began = time.perf_counter()
            self.assertIsNone(rx.search(text))
            self.assertLess(time.perf_counter() - began, 1.0, text[:30])


class StoredOnTheTask(unittest.TestCase):
    def test_the_parser_keeps_it(self):
        tmp = tempfile.TemporaryDirectory()
        try:
            t = Transcript()
            t.prompt(T0, "Research the market")
            t.say(T0 + 2, LINE + "[//]: # (task-eta: ~12 call, 3 agents, 1 long)")
            t.tool(T0 + 5, "Read", {"file_path": "/work/acme/notes.md"}, T0 + 8)
            t.say(T0 + 20, "Done.", end=True)
            t.stop(T0 + 21)
            task = task_eta.parse_transcript(t.write(os.path.join(tmp.name, ".claude", "projects")))[0]
        finally:
            remove_tmp(tmp)
        self.assertEqual((task["calls_declared"], task["agents_declared"], task["long_declared"]), (12, 3, 1))

    def test_clean_task_validates(self):
        base = {"key": "k", "start": "x", "start_ts": T0, "dur_s": 10.0, "tools": 2, "agents": 0}
        clean = task_eta.clean_task
        self.assertEqual(clean(dict(base, agents_declared=3, long_declared=1))["long_declared"], 1)
        self.assertEqual(clean(dict(base, agents_declared=0, long_declared=0))["agents_declared"], 0)
        self.assertIsNone(clean(dict(base, agents_declared="3"))["agents_declared"])
        self.assertIsNone(clean(dict(base, agents_declared=True))["agents_declared"])
        self.assertIsNone(clean(dict(base, agents_declared=2, long_declared=5))["long_declared"])
        self.assertIsNone(clean(dict(base, long_declared=1))["long_declared"])  # no agents said
        self.assertIsNone(clean(dict(base, agents_declared=-1))["agents_declared"])


class BlockText(unittest.TestCase):
    def test_the_block_asks_for_it_only_when_on(self):
        old = os.environ.get(task_eta.CALLS_LINE_ENV)
        try:
            os.environ[task_eta.CALLS_LINE_ENV] = "1"
            self.assertTrue(task_eta.calls_line_on())
        finally:
            if old is None:
                os.environ.pop(task_eta.CALLS_LINE_ENV, None)
            else:
                os.environ[task_eta.CALLS_LINE_ENV] = old
        src = open(os.path.join(REPO, "task_eta.py"), encoding="utf-8").read()
        self.assertIn("[//]: # (task-eta: ~N call, A agents, L long)", src)
        self.assertIn("run 10 minutes or more", src)


if __name__ == "__main__":
    unittest.main()
