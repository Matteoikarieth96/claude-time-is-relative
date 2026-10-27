"""Claude's own score in the [task-eta] block ("Anche Claude gioca"):
scored against what the hook offered for the kind Claude declared, never the range Claude wrote;
one line, off with `score off` or TASK_ETA_SCORE=off."""
import importlib
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import REPO, T0, Transcript, run, remove_tmp  # noqa: E402

sys.path.insert(0, REPO)
task_eta = importlib.import_module("task_eta")

LINE = "⏱ Estimated time with opus-5-5 high: ~1 min (likely 5 s to 10 min, %s)"


def task(i, real, kind="quick", est_min=1.0, session="c", rng=(0, 99999), **extra):
    t = {"start_ts": T0 + i * 600, "dur_s": real, "estimate_min": est_min, "est_range": list(rng),
         "kind_declared": kind, "session": session, "interrupted": False, "file": "/h/.claude/projects/-work-acme/c.jsonl"}
    t.update(extra)
    return t


def offers(lines, session="c", brief=None):
    """{session: [(ts, kinds, brief)]}: the hook's offer for task i at its prompt, 0.3 s later."""
    return {session: [(T0 + i * 600 + 0.3, kinds, brief) for i, kinds in enumerate(lines)]}


QUICK = {"quick": [60, 40, 90], "medium": [240, 120, 480], "agents": [2000, None, None]}


class Marks(unittest.TestCase):
    def test_hit_inside_short_long(self):
        self.assertEqual(task_eta.score_mark(64, 60, 40, 90), "hit")      # within 8%
        self.assertEqual(task_eta.score_mark(15, 10, 5, 12), "hit")       # or within 10 s
        self.assertEqual(task_eta.score_mark(85, 60, 40, 90), "inside")
        self.assertEqual(task_eta.score_mark(91, 60, 40, 90), "short")    # the estimate was too short
        self.assertEqual(task_eta.score_mark(39, 60, 40, 90), "long")     # too long: an error for Claude too
        self.assertEqual(task_eta.score_mark(85, 60, None, None), "inside")  # no range: 0.7 to 1.5 times
        self.assertEqual(task_eta.score_mark(91, 60, None, None), "short")

    def test_offer_lines(self):
        self.assertEqual(task_eta.offer_line([60, 40, 90]), (60.0, 40, 90))
        self.assertEqual(task_eta.offer_line([2000, None, None]), (2000.0, None, None))
        self.assertEqual(task_eta.offer_line([60, 90, 40]), (60.0, None, None))
        for bad in (None, [0, 1, 2], [60, 40], ["60", 40, 90], [True, 1, 2], [float("nan"), 1, 2]):
            self.assertIsNone(task_eta.offer_line(bad), bad)


class Score(unittest.TestCase):
    def test_the_hooks_range_counts_never_the_one_claude_wrote(self):
        # Claude wrote "0 to 99999 s" each time: the hook offered 40 to 90 s.
        tasks = [task(0, 62), task(1, 80), task(2, 300), task(3, 20)]
        s = task_eta.claude_score(tasks, offers([QUICK] * 4))
        self.assertEqual((s["n"], s["inside"], s["hit"], s["short"], s["long"]), (4, 2, 1, 1, 1))
        self.assertEqual((s["streak"], s["best"], s["scored"]), (0, 2, 4))

    def test_an_offer_made_for_another_model_is_not_used(self):
        # First prompt of a session whose model the hook did not know: it logged Opus's offer, the
        # task ran on Sonnet. Not scored. The same model, with or without "claude-", is.
        made = {"c": [(T0 + 0.3, QUICK, None, "opus-5-5"), (T0 + 600.3, QUICK, None, "claude-sonnet-5-5"),
                      (T0 + 1200.3, QUICK, None, None)]}
        tasks = [task(0, 62, model="sonnet-5-5"), task(1, 62, model="sonnet-5-5"), task(2, 62, model="sonnet-5-5")]
        self.assertEqual(task_eta.claude_score(tasks, made)["scored"], 2)

    def test_the_closest_offer_is_found_in_a_long_session(self):
        many = {"c": [(T0 + k * 30.0, QUICK, None) for k in range(3000, -1, -1)]}  # not in order
        found = task_eta.offer_for({"session": "c", "start_ts": T0 + 6000.4}, many)
        self.assertEqual(found[0], T0 + 6000.0)
        self.assertIsNone(task_eta.offer_for({"session": "c", "start_ts": T0 - 100}, many))

    def test_left_out_stopped_tests_unknown_kind_and_no_offer(self):
        tasks = [task(0, 62), task(1, 62, interrupted=True), task(2, 62, file="/x/-private-tmp-run/a.jsonl"),
                 task(3, 62, kind=None), task(4, 62, session="other"), task(5, 62, estimate_min=None),
                 task(6, 62, kind="veloce")]  # an older entry in Italian: still quick
        s = task_eta.claude_score(tasks, offers([QUICK] * 7))
        self.assertEqual((s["scored"], s["hit"]), (2, 2))
        self.assertIsNone(task_eta.claude_score([task(0, 62)], {}))

    def test_an_offer_logged_far_from_the_prompt_is_not_its_own(self):
        far = {"c": [(T0 + 120, QUICK, None)]}
        self.assertIsNone(task_eta.claude_score([task(0, 62)], far))

    def test_the_brief_subagents_line_when_claude_copied_it(self):
        brief = [600, 400, 900]
        s = task_eta.claude_score([task(0, 650, kind="agents", est_min=10)], offers([QUICK], brief=brief))
        self.assertEqual((s["inside"], s["short"]), (1, 0))  # 650 s in 400-900; against 2000 s it would be "long"
        s = task_eta.claude_score([task(0, 650, kind="agents", est_min=33)], offers([QUICK], brief=brief))
        self.assertEqual(s["long"], 1)

    def test_last_18_streak_and_best(self):
        reals = [62] * 15 + [300] * 10 + [62] * 3   # 15 hits, 10 too short, 3 hits
        s = task_eta.claude_score([task(i, r) for i, r in enumerate(reals)], offers([QUICK] * len(reals)))
        self.assertEqual((s["n"], s["inside"], s["short"], s["streak"], s["best"], s["scored"]), (18, 8, 10, 3, 15, 28))
        line = task_eta.score_line(s)
        self.assertEqual(line.count("\n"), 0)
        self.assertIn("last 18 estimates against this hook's range for the kind you declared: 8 inside (8 hit), "
                      "10 too short, 0 too long; streak 3, best 15/18.", line)
        self.assertIn("never the work", line)
        self.assertLess(len(line), 260)  # ~50 tokens


class Offers(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, "suggestions.jsonl")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, rows, junk=False):
        with open(path, "w") as fh:
            for i, r in enumerate(rows):
                fh.write(json.dumps(r) + "\n")
                if junk and i == 0:
                    fh.write("not json\n[1, 2]\n" + json.dumps({"ts": "x", "session": "a", "kinds": {}}) + "\n")

    def test_reads_the_tail_skips_bad_and_cut_lines(self):
        rows = [{"ts": T0 + i, "session": "a", "kinds": {"quick": [60, 40, 90]}, "brief": None} for i in range(200)]
        self.write(self.path, rows, junk=True)
        self.assertEqual(len(task_eta.hook_offers(self.path)["a"]), 200)
        size = len(json.dumps(rows[0])) + 1
        tail = task_eta.hook_offers(self.path, tail=10 * size + 5)["a"]
        self.assertEqual([o[0] for o in tail], [T0 + i for i in range(190, 200)])

    def test_a_log_just_rotated_reads_the_old_one_too(self):
        self.write(self.path + ".old", [{"ts": T0, "session": "a", "kinds": QUICK}])
        self.write(self.path, [{"ts": T0 + 1, "session": "a", "kinds": QUICK}])
        self.assertEqual([o[0] for o in task_eta.hook_offers(self.path)["a"]], [T0, T0 + 1])
        self.assertEqual(task_eta.hook_offers(os.path.join(self.tmp.name, "none.jsonl")), {})


class Block(unittest.TestCase):
    """30 tasks with no estimate, then 4 with one; the hook's log has its offer for each of the 4."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.data = os.path.join(self.home, ".claude", "task-eta")
        projects = os.path.join(self.home, ".claude", "projects")
        start = T0
        for i in range(30):
            t = Transcript(session="s%d" % i)
            start = t.task(start + 600, "Rename a variable %d" % i, steps=2 + i % 3, step_s=5)
            self.last = t.write(projects)
        self.starts = []
        for i in range(4):
            t = Transcript(session="e%d" % i)
            self.starts.append(start + 600)
            start = t.task(start + 600, "Rename the field %d" % i, steps=2, step_s=5, estimate=LINE % "quick")
            t.write(projects)
        run(["update"], self.home)
        with open(os.path.join(self.data, "index.json")) as fh:
            real = {t["session"]: t["dur_s"] for t in json.load(fh)["tasks"].values()}
        with open(os.path.join(self.data, "suggestions.jsonl"), "w") as fh:
            for i, ts in enumerate(self.starts):
                r = real["e%d" % i]
                # Three offers centred on the real time (hits); the last one far above it, though
                # inside the "5 s to 10 min" Claude wrote: too long.
                quick = [r, r * 0.6, r * 1.6] if i < 3 else [r * 3, r * 2, r * 4]
                fh.write(json.dumps({"ts": ts + 0.3, "session": "e%d" % i, "model": "opus-5-5", "effort": "high",
                                     "kinds": {"quick": quick}, "brief": None}) + "\n")

    def tearDown(self):
        remove_tmp(self.tmp)

    def block(self, env=None):
        res = run(["hook-prompt"], self.home, extra_env=env,
                  stdin=json.dumps({"prompt": "rename it", "session_id": "n", "transcript_path": self.last}))
        return json.loads(res.stdout)["hookSpecificOutput"]["additionalContext"]

    def score_lines(self, block):
        return [l for l in block.splitlines() if l.startswith("- Your score")]

    def test_one_line_with_the_score(self):
        lines = self.score_lines(self.block())
        self.assertEqual(len(lines), 1)
        self.assertIn("last 4 estimates against this hook's range for the kind you declared: 3 inside (3 hit), "
                      "0 too short, 1 too long; streak 0, best 3/4.", lines[0])

    def test_switched_off_and_on(self):
        self.assertEqual(self.score_lines(self.block({"TASK_ETA_SCORE": "off"})), [])
        out = run(["score", "off"], self.home).stdout
        self.assertIn("off", out.splitlines()[0])
        self.assertTrue(os.path.exists(os.path.join(self.data, "score.off")))
        self.assertEqual(self.score_lines(self.block()), [])
        out = run(["score", "on"], self.home).stdout
        self.assertIn("3 inside (3 hit)", out)
        self.assertEqual(len(self.score_lines(self.block())), 1)
        data = json.loads(run(["score", "--json"], self.home).stdout)
        self.assertEqual((data["on"], data["score"]["long"], data["score"]["scored"]), (True, 1, 4))


if __name__ == "__main__":
    unittest.main()
