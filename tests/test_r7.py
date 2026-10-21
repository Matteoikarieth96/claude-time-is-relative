"""Round 7 (100 benchmark runs in blocks of 10): what changed to close the gap between the
estimate and the real time. Synthetic transcripts only."""
import importlib
import json
import time
import os
import sys
import tempfile
import unittest
import unittest.mock

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

    def test_brief_means_every_subagent_under_10_minutes(self):
        self.assertIs(task_eta.agents_brief(agent_task(T0, 600, [60, 120, 540])), True)
        # One long subagent makes the task "with subagents" (the median would have said brief).
        self.assertIs(task_eta.agents_brief(agent_task(T0, 3000, [180, 180, 180, 1800, 2400])), False)
        self.assertIsNone(task_eta.agents_brief(fake_task("opus-5-5", "xhigh", T0)))
        for odd in (["60", True], [float("nan")], [float("inf")], [-5]):
            self.assertIsNone(task_eta.agents_brief(agent_task(T0, 600, odd)), odd)  # odd records ignored

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


class BigWrites(unittest.TestCase):
    """A Write or Edit of about 150 lines or more counts as 3 tool calls for the kinds."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.projects = os.path.join(self.tmp.name, ".claude", "projects")

    def tearDown(self):
        remove_tmp(self.tmp)

    def test_written_chars(self):
        self.assertEqual(task_eta.written_chars({"content": "abc"}), 3)
        self.assertEqual(task_eta.written_chars({"new_string": "ab", "old_string": "zzzz"}), 2)
        self.assertEqual(task_eta.written_chars({"edits": [{"new_string": "ab"}, {"new_string": "cde"}, "x", {}]}), 5)
        for odd in (None, "text", ["content"], {"content": 5}, {"edits": "abc"}):
            self.assertEqual(task_eta.written_chars(odd), 0, odd)

    def test_a_big_write_moves_a_task_up_a_kind(self):
        t = Transcript()
        t.prompt(T0, "Build the dashboard page")
        big = "x" * task_eta.BIG_WRITE_CHARS
        t.tool(T0 + 5, "Write", {"file_path": "/work/acme/app.html", "content": big}, T0 + 90)
        t.tool(T0 + 95, "Write", {"file_path": "/work/acme/test.js", "content": "small"}, T0 + 100)
        t.tool(T0 + 105, "Bash", {"command": "node test.js"}, T0 + 110)
        t.say(T0 + 115, "Done.", end=True)
        t.stop(T0 + 116)
        task = task_eta.parse_transcript(t.write(self.projects))[0]
        self.assertEqual((task["big_writes"], task_eta.work_tools(task), task_eta.work_units(task)), (1, 3, 5))
        self.assertEqual(task_eta.task_kind(task), "medium")  # 3 calls alone would be "quick"

    def test_bad_stored_counts_become_zero(self):
        for bad in ("2", True, -1, 1.5):
            task = fake_task("opus-5-5", "high", T0)
            task.update(key="k", start="x", big_writes=bad)
            self.assertEqual(task_eta.clean_task(task)["big_writes"], 0, bad)


class EtaByDeclaredKind(unittest.TestCase):
    def past(self, n, tools, dur, marks):
        out = []
        for i in range(n):
            t = fake_task("opus-5-5", "xhigh", T0 + 1000 * len(marks) + i + tools * 100000, dur=dur)
            t.update(tools=tools, proto=0, call_marks=marks)
            out.append(t)
        return out

    def test_the_declared_kind_picks_the_past_tasks(self):
        quick = self.past(30, 2, 40.0, [0.0, 10.0, 20.0])          # done soon after call 2
        long_ = self.past(30, 20, 900.0, [0.0, 10.0, 20.0, 30.0])   # still far from done
        now = dict(fake_task("opus-5-5", "xhigh", T0 + 10 ** 7, dur=25.0), call_marks=[0.0, 10.0, 20.0],
                   tools=2, proto=0, kind_declared="long")
        left_long = task_eta.eta_for(now, quick + long_)[0]
        self.assertAlmostEqual(left_long, 875.0)
        left_all = task_eta.progressive_eta(now, quick + long_)[0]
        self.assertLess(left_all, left_long)  # the quick ones pull the mixed answer down
        now["kind_declared"] = None
        self.assertEqual(task_eta.eta_for(now, quick + long_)[0], left_all)

    def test_too_few_of_the_kind_falls_back_to_all(self):
        quick = self.past(30, 2, 40.0, [0.0, 10.0, 20.0])
        long_ = self.past(5, 20, 900.0, [0.0, 10.0, 20.0, 30.0])
        now = dict(fake_task("opus-5-5", "xhigh", T0 + 10 ** 7, dur=25.0), call_marks=[0.0, 10.0, 20.0],
                   tools=2, proto=0, kind_declared="long")
        self.assertEqual(task_eta.eta_for(now, quick + long_), task_eta.progressive_eta(now, quick + long_))


class ReviewFixes(unittest.TestCase):
    """Findings of the independent review of round 7's changes."""

    def test_model_family_reads_provider_names(self):
        for name, family in (("opus-5-5", "opus"), ("us.anthropic.claude-opus-5-5-v1:0", "opus"),
                             ("anthropic/claude-sonnet-5.5", "sonnet"), ("3-5-haiku", "haiku"),
                             ("fable-5-1", "fable"), ("gpt-9", "gpt-9")):
            self.assertEqual(task_eta.model_family(name), family, name)
        work = [fake_task("us.anthropic.claude-opus-5-5-v1:0", "high", T0 + i) for i in range(5)]
        lat = {"us.anthropic.claude-opus-5-5-v1:0|high": (14.0, 900),
               "us.anthropic.claude-sonnet-5-5-v1:0|high": (8.0, 400),
               "us.anthropic.claude-haiku-5-5-v1:0|medium": (7.0, 300)}
        with unittest.mock.patch.object(task_eta, "valid_model", lambda m: m):
            combos = task_eta.main_combos(work, lat=lat)
        self.assertEqual(len(combos), 3, combos)
        # A model only the speed table knows gets its most measured effort, not a guess.
        self.assertIn(("us.anthropic.claude-sonnet-5-5-v1:0", "high"), combos)

    def test_infinite_or_negative_numbers_are_dropped(self):
        task = fake_task("opus-5-5", "high", T0)
        task.update(key="k", start="x", calls_by={"opus-5-5|high": [40, float("inf")], "opus-5-5|low": [3, 9.0]},
                    call_marks=[0.0, float("nan"), -1, 5.0],
                    sub={"agents": [{"prompt": "p", "dur_s": float("inf")}, {"prompt": "q", "dur_s": 60}],
                         "busy_s": 1, "work_s": 1, "calls_by": {"opus-5-5|high": [1, float("nan")]}})
        clean = task_eta.clean_task(task)
        self.assertEqual(clean["calls_by"], {"opus-5-5|low": [3, 9.0]})
        self.assertEqual(clean["call_marks"], [0.0, 5.0])
        self.assertEqual([a["prompt"] for a in clean["sub"]["agents"]], ["q"])
        self.assertEqual(clean["sub"]["calls_by"], {})

    def test_a_nan_accuracy_in_the_calibration_is_not_shown(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(remove_tmp, tmp)
        path = os.path.join(tmp.name, "predictor.json")
        with open(path, "w") as fh:
            fh.write('{"version": 2, "kinds": {"quick": {"lo": 0.5, "hi": 1.8, "n": 40, "tested": 30, '
                     '"within_2x": NaN, "coverage": 0.5}}, "work_tasks": 40, "at": 1}')
        with unittest.mock.patch.object(task_eta, "PREDICTOR", path):
            data = task_eta.load_predictor()
        self.assertEqual(data["kinds"]["quick"]["tested"], 0)


class MacSleep(unittest.TestCase):
    """Time the Mac slept is left out of a task's duration."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.projects = os.path.join(self.tmp.name, ".claude", "projects")
        self.sleeps = os.path.join(self.tmp.name, "sleeps.json")
        patch = unittest.mock.patch.object(task_eta, "SLEEPS", self.sleeps)
        patch.start()
        self.addCleanup(patch.stop)
        task_eta._SLEEPS[:] = [None, [], []]

    def tearDown(self):
        task_eta._SLEEPS[:] = [None, [], []]
        remove_tmp(self.tmp)

    def write_sleeps(self, pairs):
        with open(self.sleeps, "w") as fh:
            json.dump(pairs, fh)
        os.utime(self.sleeps, (T0 + len(pairs), T0 + len(pairs) + 0.5))

    def task_with_gap(self):
        """An Agent call, then 20 minutes until the next record (the agent still running)."""
        t = Transcript()
        t.prompt(T0, "Research the topic with subagents")
        t.tool(T0 + 5, "Agent", {"prompt": "dig"}, T0 + 1300)
        t.say(T0 + 1310, "Done.", end=True)
        t.stop(T0 + 1311)
        return t.write(self.projects)

    def test_a_recorded_sleep_inside_a_gap_is_left_out(self):
        path = self.task_with_gap()
        plain = task_eta.parse_transcript(path)[0]["dur_s"]
        self.write_sleeps([[T0 + 100, T0 + 1000], [T0 + 5000, T0 + 6000]])
        task = task_eta.parse_transcript(path)[0]
        self.assertAlmostEqual(plain - task["dur_s"], 900.0)
        self.assertEqual(task["slept_s"], 900.0)

    def test_overlap_and_bad_records(self):
        self.write_sleeps([[T0, T0 + 60], [T0 + 200, T0 + 100], ["x", 5], [T0 + 50, T0 + 70],
                           [T0 + 300, T0 + 10 ** 7], [float("nan"), T0], True, [T0 + 500, T0 + 560]])
        starts, wakes = task_eta.load_sleeps()
        self.assertEqual(list(zip(starts, wakes)), [(T0, T0 + 60), (T0 + 500, T0 + 560)])
        self.assertEqual(task_eta.sleep_overlap(T0 + 30, T0 + 530), 60.0)
        self.assertEqual(task_eta.sleep_overlap(T0 + 600, T0 + 700), 0.0)
        self.assertEqual(task_eta.sleep_overlap(T0 + 10, T0), 0.0)

    def test_record_sleep_adds_each_pair_once(self):
        now = time.time()
        with unittest.mock.patch.object(task_eta, "read_sleep_pair", return_value=(now - 900, now - 300)):
            task_eta.record_sleep()
            task_eta.record_sleep()
        with open(self.sleeps) as fh:
            self.assertEqual(len(json.load(fh)), 1)
        self.assertEqual(task_eta.stat.S_IMODE(os.stat(self.sleeps).st_mode) if hasattr(task_eta, "stat")
                         else os.stat(self.sleeps).st_mode & 0o777, 0o600)
        for bad in (None, (now, now - 5), (0, 0), (now - 10 ** 7, now), (now + 3600, now + 7200)):
            with unittest.mock.patch.object(task_eta, "read_sleep_pair", return_value=bad):
                task_eta.record_sleep()
        with open(self.sleeps) as fh:
            self.assertEqual(len(json.load(fh)), 1)

    def test_the_kernel_answers_on_a_mac(self):
        pair = task_eta.read_sleep_pair()
        if sys.platform != "darwin":
            self.assertIsNone(pair)
        elif pair is not None:
            self.assertTrue(all(isinstance(x, float) for x in pair))

    def test_pmset_log_pairs(self):
        log = "\n".join([
            "2026-01-10 08:00:00 +0000 Sleep               \tEntering Sleep state due to 'Idle Sleep'",
            "2026-01-10 08:00:01 +0000 Wake Requests       \t[process=dasd request=SleepService]",
            "2026-01-10 08:00:27 +0000 DarkWake            \tDarkWake from Deep Idle",
            "2026-01-10 08:01:00 +0000 Sleep               \tEntering Sleep state",
            "2026-01-10 08:16:15 +0000 Wake                \tWake from Deep Idle",
            "2026-01-10 08:20:00 +0000 Wake                \tno sleep before this one",
            "garbage line",
        ])
        pairs = task_eta.parse_pmset_sleeps(log)
        self.assertEqual([round(b - a) for a, b in pairs], [27, 915])


if __name__ == "__main__":
    unittest.main()
