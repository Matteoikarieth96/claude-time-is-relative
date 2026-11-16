"""v6 (review 2026-11-16): each line is scaled by how the user's earlier lines of the same declared
kind and prompt length turned out. The factor is learned against the line as it would have been
without scaling, is checked out of sample, and is used only while it brought the ~ value closer
and the range held at least as often."""
import importlib
import json
import math
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import REPO, T0, Transcript, remove_tmp, run  # noqa: E402

sys.path.insert(0, REPO)
task_eta = importlib.import_module("task_eta")

LINE = "⏱ Estimated time with opus-5-5 high: ~2 min (likely 1 to 4 min, medium)"


class Factor(unittest.TestCase):
    def test_prompt_bands(self):
        self.assertEqual([task_eta.prompt_band(t) for t in (None, "", "x" * 24, "x" * 25, "x" * 99, "x" * 100, "x" * 300)],
                         [0, 0, 0, 1, 1, 2, 2])

    def test_no_lines_no_factor(self):
        self.assertEqual(task_eta.declared_factor([], 0), 1.0)
        self.assertEqual(task_eta.shrunk_median([]), 0.0)

    def test_few_lines_barely_move_it(self):
        half = math.log(0.5)
        two = task_eta.declared_factor([(half, 1)] * 2, 2)   # 2 lines: 2/12 of the way
        many = task_eta.declared_factor([(half, 1)] * 90, 2)  # 90 lines: 9/10 of the way
        self.assertAlmostEqual(two, 0.5 ** (2 / 12), places=6)
        self.assertAlmostEqual(many, 0.5 ** 0.9, places=6)

    def test_prompt_band_adds_its_own_part(self):
        # Lines of one label: short prompts finished at 0.6x the ~ value, long ones at 1.2x.
        rows = [(math.log(0.6), 0), (math.log(1.2), 2)] * 30
        short, long_ = task_eta.declared_factor(rows, 0), task_eta.declared_factor(rows, 2)
        self.assertLess(short, 0.75)
        self.assertGreater(long_, 1.0)
        self.assertLess(short, task_eta.declared_factor(rows, 1))  # a band with no lines gets the label's own
        self.assertLess(task_eta.declared_factor(rows, 1), long_)

    def test_only_the_last_lines_count(self):
        old = [(math.log(3.0), 0)] * 400
        new = [(0.0, 0)] * task_eta.ADJ_WINDOW
        self.assertAlmostEqual(task_eta.declared_factor(old + new, 0), 1.0, places=6)

    def test_factor_is_clamped(self):
        self.assertEqual(task_eta.declared_factor([(math.log(0.01), 0)] * 200, 0), task_eta.ADJ_CLAMP[0])
        self.assertEqual(task_eta.declared_factor([(math.log(50.0), 0)] * 200, 0), task_eta.ADJ_CLAMP[1])


def adjust(on=True, medium=(0.5, 0.6, 0.7), **more):
    labels = {"medium": {"n": 40, "bands": [20, 10, 10], "factor": list(medium)}}
    labels.update(more)
    return {"labels": labels, "on": on, "spans": [[1.0, None]],
            "check": {"n": 40, "miss": [2.0, 1.5], "ranged": 30, "held": [15, 20]}}


class StoredFactor(unittest.TestCase):
    def test_a_good_one_is_kept(self):
        adj = task_eta.valid_adjust(adjust())
        self.assertTrue(adj["on"])
        self.assertEqual(task_eta.line_factor({"adjust": adj}, "medium", 1), 0.6)
        self.assertEqual(task_eta.line_factor({"adjust": adj}, "long", 1), 1.0)   # no lines of that label
        self.assertEqual(task_eta.line_factor({"adjust": adj}, "medium", None), 1.0)  # no prompt band: as measured

    def test_off_means_no_scaling(self):
        adj = task_eta.valid_adjust(adjust(on=False))
        self.assertEqual(task_eta.line_factor({"adjust": adj}, "medium", 0), 1.0)
        self.assertEqual(task_eta.line_factor(None, "medium", 0), 1.0)
        self.assertEqual(task_eta.line_factor({}, "medium", 0), 1.0)

    def test_bad_values_are_dropped(self):
        for bad in ([0.5, 0.6], [0.5, 0.6, 9.0], [0.5, "0.6", 0.7], [0.5, float("nan"), 0.7], [True, 0.6, 0.7], "x", None):
            adj = task_eta.valid_adjust(adjust(medium=bad) if isinstance(bad, list) else
                                        dict(adjust(), labels={"medium": {"factor": bad}}))
            self.assertEqual(adj["labels"], {}, bad)
            self.assertEqual(task_eta.line_factor({"adjust": adj}, "medium", 0), 1.0)
        self.assertEqual(task_eta.valid_adjust(adjust(evil={"factor": [1.0, 1.0, 1.0]}))["labels"].keys(), {"medium"})
        for bad in (None, "x", [], {"labels": []}):
            self.assertIsNone(task_eta.valid_adjust(bad))

    def test_no_check_no_scaling(self):
        for check in (None, {"n": 40}, {"n": 40, "miss": [2.0], "ranged": 3, "held": [1, 2]},
                      {"n": 40, "miss": [2.0, 0.2], "ranged": 3, "held": [1, 2]},
                      {"n": 40, "miss": [2.0, 1.5], "ranged": 3, "held": [1, 9]}):
            adj = task_eta.valid_adjust(dict(adjust(), check=check))
            self.assertFalse(adj["on"], check)
            self.assertIsNone(adj["check"])

    def test_spans_are_checked(self):
        good = [[1.0, 5.0], [9.0, None]]
        self.assertEqual(task_eta.valid_adjust(dict(adjust(), spans=good))["spans"], good)
        for bad in (None, "x", [[1.0]], [[5.0, 1.0]], [["a", None]], [[1.0, None], 3], [[True, None]], [[float("inf"), None]]):
            self.assertEqual(task_eta.valid_adjust(dict(adjust(), spans=bad))["spans"], [], bad)
        many = [[float(i), float(i)] for i in range(50)]
        self.assertEqual(task_eta.valid_adjust(dict(adjust(), spans=many))["spans"], many[-task_eta.ADJ_SPANS:])

    def test_used_only_while_it_helps(self):
        n = task_eta.ADJ_MIN_CHECK
        self.assertTrue(task_eta.factor_helps(n, [1.8, 1.7], [20, 22]))
        self.assertTrue(task_eta.factor_helps(n, [1.8, 1.8], [20, 20]))
        self.assertFalse(task_eta.factor_helps(n - 1, [1.8, 1.7], [20, 22]))  # too few lines tested
        self.assertFalse(task_eta.factor_helps(n, [1.8, 1.9], [20, 22]))      # the ~ value got further
        self.assertFalse(task_eta.factor_helps(n, [1.8, 1.7], [20, 19]))      # the range held less often

    def test_switch_off(self):
        corr = {"adjust": task_eta.valid_adjust(adjust())}
        task_eta.DECLARED_FACTOR = False
        try:
            self.assertEqual(task_eta.line_factor(corr, "medium", 0), 1.0)
        finally:
            task_eta.DECLARED_FACTOR = True


class FakePredictor:
    """Kind medians only: what kind_estimates and brief_estimate ask a Predictor for."""
    MEDIANS = {("quick", None): 40.0, ("medium", None): 100.0, ("long", None): 400.0, ("agents", None): 1500.0,
               ("agents", False): 1800.0, ("agents", True): 600.0}

    def category_median(self, cat, model, effort, kind=None, brief=None):
        return self.MEDIANS.get((kind, brief))


class ScaledLines(unittest.TestCase):
    KINDS = {k: {"lo": 0.5, "hi": 2.0, "n": 30} for k in task_eta.KINDS}

    def corr(self, **factors):
        labels = {k: {"n": 40, "bands": [40, 0, 0], "factor": [f, 1.0, 1.0]} for k, f in factors.items()}
        return {"kinds": self.KINDS, "adjust": task_eta.valid_adjust(dict(adjust(), labels=labels))}

    def test_value_and_range_move_together(self):
        pred, corr = FakePredictor(), self.corr(medium=0.7, agents=0.8, agents_brief=1.5)
        plain = task_eta.kind_estimates(pred, corr, "opus-5-5", "high")
        self.assertEqual(plain["medium"], (100.0, 50.0, 200.0))
        scaled = task_eta.kind_estimates(pred, corr, "opus-5-5", "high", 0)
        self.assertEqual(scaled["quick"], plain["quick"])
        self.assertEqual(scaled["medium"], (70.0, 35.0, 140.0))
        self.assertEqual(scaled["long"], plain["long"])
        self.assertEqual(scaled["agents"], (1440.0, 720.0, 2880.0))
        self.assertEqual(task_eta.kind_estimates(pred, corr, "opus-5-5", "high", 1), plain)  # another prompt band
        self.assertEqual(task_eta.brief_estimate(pred, corr, "opus-5-5", "high"), (600.0, 300.0, 1200.0))
        self.assertEqual(task_eta.brief_estimate(pred, corr, "opus-5-5", "high", 0), (900.0, 450.0, 1800.0))
        # Never above the "with subagents" line as printed.
        self.assertEqual(task_eta.brief_estimate(pred, corr, "opus-5-5", "high", 0, top=720.0), (720.0, 360.0, 1440.0))
        self.assertEqual(task_eta.brief_estimate(pred, corr, "opus-5-5", "high", 0, top=1440.0), (900.0, 450.0, 1800.0))

    def test_lines_stay_in_order(self):
        pred, corr = FakePredictor(), self.corr(quick=2.0, medium=0.5)
        scaled = task_eta.kind_estimates(pred, corr, "opus-5-5", "high", 0)
        self.assertEqual(scaled["quick"][0], 80.0)
        self.assertEqual(scaled["medium"][0], 80.0)  # 100 x 0.5 would fall under the quick line
        self.assertEqual(scaled["long"][0], 400.0)

    def test_block_names_the_factor_the_line_carries(self):
        # quick x2.0 lifts the medium line above its own x0.5: the block and the log must say x0.80, not x0.50.
        pred, corr = FakePredictor(), self.corr(quick=2.0, medium=0.5)
        scaled, plain = (task_eta.kind_estimates(pred, corr, "opus-5-5", "high", b) for b in (0, None))
        self.assertEqual(scaled["medium"][0] / plain["medium"][0], 0.8)

    def test_note_names_only_scaled_lines(self):
        corr = self.corr(medium=0.7)
        note = task_eta.scaling_line(corr, {"quick": 1.0, "medium": 0.7, "long": 1.004})
        self.assertIn("(medium x0.70)", note)
        self.assertIn("1.50x with the scaling and 2.00x without", note)
        self.assertIn("on 40 of your last lines", note)
        self.assertIn("on the 30 of them with a range it held 67% against 50%", note)
        self.assertIsNone(task_eta.scaling_line(corr, {"quick": 1.0, "medium": 1.0}))
        self.assertIsNone(task_eta.scaling_line({}, {"medium": 0.7}))


class DeclaredLine(unittest.TestCase):
    def task(self, kind, minutes):
        return {"kind_declared": kind, "estimate_min": minutes, "model": "opus-5-5", "effort": "high"}

    def test_the_line_as_offered_without_scaling(self):
        pred = FakePredictor()
        self.assertEqual(task_eta.declared_line(pred, self.task("medium", 1.0)), ("medium", 100.0))
        self.assertEqual(task_eta.declared_line(pred, self.task("agents", 30.0)), ("agents", 1800.0))
        self.assertEqual(task_eta.declared_line(pred, self.task("agents", 11.0)), ("agents_brief", 600.0))
        for none in (self.task(None, 2.0), self.task("medium", None), self.task("medium", 0), self.task("text", 2.0)):
            self.assertIsNone(task_eta.declared_line(pred, none))

    def test_a_scaled_line_with_subagents_is_told_apart(self):
        # "~17 min": nearer the brief line (10 min) as measured, but it is the long line (30 min) x0.55.
        pred, task = FakePredictor(), self.task("agents", 17.0)
        self.assertEqual(task_eta.declared_line(pred, task)[0], "agents_brief")
        scale = {"agents": 0.55, "agents_brief": 0.8}.get
        self.assertEqual(task_eta.declared_line(pred, task, scale), ("agents", 1800.0))


class EndToEnd(unittest.TestCase):
    """60 tasks that all open with the "medium" line; two in three turn out quick, at about 0.35x the line."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        projects = os.path.join(self.home, ".claude", "projects")
        for i in range(60):
            t = Transcript(session="s%d" % i)
            steps, step_s = (6, 14 + 4 * (i % 5)) if i % 3 == 0 else (3, 10 + 3 * (i % 4))
            t.task(T0 + 3600 * i, "Fix bug number %d" % i, steps=steps, step_s=step_s, estimate=LINE)
            t.write(projects)
        self.data = os.path.join(self.home, ".claude", "task-eta")

    def tearDown(self):
        remove_tmp(self.tmp)

    def calibrate(self):
        res = run(["calibrate"], self.home)
        self.assertEqual(res.returncode, 0, res.stderr)
        with open(os.path.join(self.data, "predictor.json"), encoding="utf-8") as fh:
            return json.load(fh)["adjust"]

    def test_factor_learned_checked_and_stable(self):
        adj = self.calibrate()
        self.assertEqual(set(adj["labels"]), {"medium"})
        medium = adj["labels"]["medium"]
        self.assertEqual(medium["bands"], [medium["n"], 0, 0])
        self.assertGreater(medium["n"], 45)              # the first tasks have no line to replay yet
        self.assertEqual(medium["factor"][0], 0.5)       # about 0.35x, clamped
        self.assertLess(medium["factor"][1], 0.6)        # a prompt band with no lines: the label's own part
        self.assertTrue(adj["on"])
        check = adj["check"]
        self.assertEqual(check["n"], medium["n"] - 10)   # the first 10 lines only teach
        self.assertLess(check["miss"][1], check["miss"][0])
        self.assertGreater(check["held"][1], check["held"][0])
        self.assertLessEqual(check["held"][1], check["ranged"])
        # Learned against the unscaled line: a second run, now that lines "carry" the factor, finds the same.
        self.assertEqual(len(adj["spans"]), 1)
        self.assertIsNone(adj["spans"][0][1])            # on since this run
        again = self.calibrate()
        self.assertEqual(again["labels"], adj["labels"])
        self.assertEqual(again["spans"], adj["spans"])

    def test_block_report_and_log_show_it(self):
        self.calibrate()
        res = run(["estimate", "Fix bug number 61"], self.home)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("already scaled by how your earlier lines of the same declared kind and prompt length", res.stdout)
        self.assertIn("(medium x0.50)", res.stdout)
        lines = [l for l in res.stdout.splitlines() if l.startswith("⏱") and l.endswith(", medium)")]
        self.assertTrue(lines and all(": ~1 min (" in l for l in lines), res.stdout)  # ~2 min as measured
        res = run(["report"], self.home)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("Scaling of the lines by declared kind and prompt length", res.stdout)
        self.assertIn("learned from your last lines of that kind): on.", res.stdout)
        self.assertRegex(res.stdout, r"Out of sample on \d+ lines: the ~ value was typically off 1\.\d\dx with the "
                                     r"scaling, [23]\.\d\dx without; the range held \d+% against \d+% ")
        run(["hook-prompt"], self.home, stdin=json.dumps({"prompt": "Fix bug number 62", "session_id": "s62",
                                                           "cwd": "/work/acme"}))
        with open(os.path.join(self.data, "suggestions.jsonl"), encoding="utf-8") as fh:
            rec = json.loads(fh.read().splitlines()[-1])
        self.assertEqual((rec["band"], rec["adj"]["medium"], rec["adj"]["quick"]), (0, 0.5, 1.0))
        self.assertNotIn("prompt", rec)

    def test_off_when_the_range_holds_less(self):
        self.calibrate()
        path = os.path.join(self.data, "predictor.json")
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertTrue(task_eta.valid_adjust(data["adjust"])["on"])
        data["adjust"]["on"] = False  # what calibrate writes when the range held less often with the factor
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh)
        res = run(["estimate", "Fix bug number 61"], self.home)
        self.assertNotIn("already scaled", res.stdout)
        lines = [l for l in res.stdout.splitlines() if l.startswith("⏱") and l.endswith(", medium)")]
        self.assertTrue(lines and all(": ~2 min (" in l for l in lines), res.stdout)

    def test_off_when_it_does_not_help(self):
        # Every task is what its line said: nothing to correct, and too few lines tested to switch on.
        home = tempfile.TemporaryDirectory()
        try:
            projects = os.path.join(home.name, ".claude", "projects")
            for i in range(30):
                t = Transcript(session="m%d" % i)
                t.task(T0 + 3600 * i, "Fix bug number %d" % i, steps=6, step_s=20, estimate=LINE)
                t.write(projects)
            res = run(["calibrate"], home.name)
            self.assertEqual(res.returncode, 0, res.stderr)
            with open(os.path.join(home.name, ".claude", "task-eta", "predictor.json"), encoding="utf-8") as fh:
                adj = json.load(fh)["adjust"]
            self.assertFalse(adj["on"])
            self.assertEqual(adj["spans"], [])
            res = run(["estimate", "Fix bug number 61"], home.name)
            self.assertNotIn("already scaled", res.stdout)
            res = run(["report"], home.name)
            self.assertIn("off until 30 lines are tested", res.stdout)
        finally:
            remove_tmp(home)


def write_tasks(projects, plan, line=LINE, prefix="t"):
    """One session per task, an hour apart: plan = [(steps, seconds per step)], every task opens with `line`."""
    for i, (steps, step_s) in enumerate(plan):
        t = Transcript(session="%s%d" % (prefix, i))
        t.task(T0 + 3600 * i, "Fix bug number %d" % i, steps=steps, step_s=step_s, estimate=line)
        t.write(projects)


class Learning(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.projects = os.path.join(self.home, ".claude", "projects")
        self.predictor = os.path.join(self.home, ".claude", "task-eta", "predictor.json")

    def tearDown(self):
        remove_tmp(self.tmp)

    def calibrate(self):
        res = run(["calibrate"], self.home)
        self.assertEqual(res.returncode, 0, res.stderr)
        with open(self.predictor, encoding="utf-8") as fh:
            return json.load(fh)

    def test_learned_against_the_line_as_measured_not_as_printed(self):
        # Two in three tasks take about 0.7x the medium line as measured (~2 min). Every line says "~9 min":
        # against the printed value the factor would hit the clamp (0.5).
        plan = [(6, 20) if i % 3 == 0 else (3, 28) for i in range(60)]
        write_tasks(self.projects, plan, line="⏱ Estimated time with opus-5-5 high: ~9 min (likely 4 to 20 min, medium)")
        factor = self.calibrate()["adjust"]["labels"]["medium"]["factor"][0]
        self.assertGreater(factor, 0.65)
        self.assertLess(factor, 0.9)

    def test_check_uses_only_the_lines_before(self):
        # 25 tasks as the line says, then 25 at 0.4x: until the last one the earlier lines are mostly on
        # the mark, so out of sample the factor stays near 1 and the miss does not improve. Scored with
        # all the lines (in sample) it would drop from 2.5x to about 1.6x.
        write_tasks(self.projects, [(6, 20)] * 25 + [(3, 15)] * 25)
        adj = self.calibrate()["adjust"]
        check = adj["check"]
        self.assertGreater(check["miss"][0], 2.2)
        self.assertGreater(check["miss"][1], 2.2)
        self.assertLess(adj["labels"]["medium"]["factor"][0], 0.85)  # what the next line gets, from all 50

    def test_lines_reach_further_back_than_the_accuracy(self):
        # 340 tasks: the factor learns from the lines of all of them, the accuracy and the check keep the last 300.
        write_tasks(self.projects, [(6, 14 + 4 * (i % 5)) if i % 3 == 0 else (3, 10 + 3 * (i % 4)) for i in range(340)])
        data = self.calibrate()
        adj = data["adjust"]
        self.assertGreater(adj["labels"]["medium"]["n"], 300)
        self.assertLessEqual(adj["labels"]["medium"]["n"], 340)
        self.assertEqual(adj["check"]["n"], 300)
        self.assertEqual(data["n"], 300)
        self.assertEqual(sum(k["n"] for k in data["kinds"].values()), 300)
        # The accuracy by kind is what it is with the factor switched off (the last 300 tasks, same replay).
        res = run(["calibrate"], self.home, extra_env={"TASK_ETA_NO_SCALING": "1"})
        self.assertEqual(res.returncode, 0, res.stderr)
        with open(self.predictor, encoding="utf-8") as fh:
            off = json.load(fh)
        self.assertIsNone(off["adjust"])
        for key in ("kinds", "n", "kind_hits", "kind_misses", "q25", "q75", "within_2x", "printed"):
            self.assertEqual(off[key], data[key], key)
        res = run(["estimate", "Fix bug number 341"], self.home, extra_env={"TASK_ETA_NO_SCALING": "1"})
        self.assertNotIn("already scaled", res.stdout)

    def test_a_stretch_with_the_factor_on_is_replayed(self):
        # The lines of these tasks were printed while the factor was on (a span that covers them): same result.
        plan = [(6, 14 + 4 * (i % 5)) if i % 3 == 0 else (3, 10 + 3 * (i % 4)) for i in range(60)]
        write_tasks(self.projects, plan)
        first = self.calibrate()["adjust"]
        with open(self.predictor, encoding="utf-8") as fh:
            data = json.load(fh)
        data["adjust"]["spans"] = [[T0 - 10, T0 + 3600 * 30], [T0 + 3600 * 40, None]]
        with open(self.predictor, "w", encoding="utf-8") as fh:
            json.dump(data, fh)
        again = self.calibrate()["adjust"]
        self.assertEqual(again["labels"], first["labels"])
        self.assertEqual(again["spans"], data["adjust"]["spans"])  # still on: the open span stays


if __name__ == "__main__":
    unittest.main()
