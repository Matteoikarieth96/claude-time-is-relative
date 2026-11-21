"""The compact form of the hook's block (TASK_ETA_BLOCK=compact in the hooks' environment): off unless
asked for, the same ready lines and closing command as the full block, a quarter of its size.
Synthetic data only."""
import importlib
import json
import os
import re
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import REPO, T0, Transcript, iso, remove_tmp, run  # noqa: E402

sys.path.insert(0, REPO)
task_eta = importlib.import_module("task_eta")
SPREAD = (0.4, 1.0, 2.5, 0.7, 1.6, 0.25, 1.2, 3.0, 0.9, 0.5)
# A command of ordinary length (python3 and a clone in the home folder), so the size does not depend on
# where the tests run. The whole block grows by one character for each character of this command.
COMMAND = "/usr/bin/python3 /Users/someone/claude-time-is-relative/task_eta.py"
SIZE_TARGET = 900  # characters of a compact block with all five lines and a command like the one above
WORDS_TARGET = 420  # the same, without the ready lines and the command: what the compact form itself writes


def fake(i, dur, tools=2, subs=None):
    """A finished task of the project -work-acme, i * 4000 s after T0; `subs` = its subagents' run times."""
    start = T0 + i * 4000
    task = {"key": "k%d" % i, "start": iso(start), "start_ts": start, "end_ts": start + dur, "dur_s": dur,
            "tools": tools, "proto": 0, "book": 0, "agents": len(subs or ()), "big_writes": 0, "interrupted": False,
            "monitor": False, "open": False, "model": "opus-5-5", "effort": "xhigh",
            "calls_by": {"opus-5-5|xhigh": [4, 60.0], "sonnet-5-5|high": [4, 30.0]},
            "file": "/p/-work-acme/s.jsonl", "prompt": "Fix the login bug in module %d" % i, "headless": False}
    if subs:
        task["sub"] = {"agents": [{"prompt": "p", "dur_s": d} for d in subs], "busy_s": 0, "work_s": 0, "calls_by": {}}
    return task


def history():
    """Past tasks of every kind: quick, medium, long, with brief subagents, with subagents."""
    tasks = []
    for n, (dur, tools, subs) in enumerate(((40, 2, None), (150, 8, None), (600, 30, None),
                                            (700, 8, [120, 300]), (3000, 8, [1500, 2400]))):
        tasks += [fake(n * 100 + i, dur * SPREAD[i % 10], tools, subs) for i in range(20)]
    return {"tasks": {t["key"]: t for t in tasks}}


def calibration(misses=(3, 4)):
    """A predictor.json as load_predictor returns it: every kind with a range and a record, the
    "medium" line scaled (x0.6 for a prompt of 25 to 99 characters)."""
    kind = {"factor": 1.0, "lo": 0.5, "hi": 2.5, "n": 60, "q": 0.2, "tested": 40, "within_2x": 0.8,
            "coverage": 0.72, "early": 0.1}
    scaling = task_eta.valid_adjust({
        "labels": {"medium": {"n": 40, "bands": [20, 10, 10], "factor": [0.5, 0.6, 0.7]}}, "on": True,
        "spans": [[1.0, None]], "check": {"n": 40, "miss": [2.0, 1.5], "ranged": 30, "held": [15, 20]}})
    return {"version": 2, "kinds": {k: dict(kind) for k in task_eta.KINDS}, "kind_hits": [30, 37],
            "kind_misses": list(misses), "work_tasks": 100, "at": T0, "adjust": scaling,
            "printed": {"since": T0, "all": [68, 39, 6], "right": [44, 30, 4], "wrong": [24, 9, 2],
                        "kinds": {"quick": [17, 6, 1], "medium": [29, 20, 3], "long": [10, 8, 1], "agents": [12, 5, 1]}}}


def block(compact, current=("opus-5-5", "xhigh"), env=None, info=None, corr=None):
    """The hook's block for a prompt close to the past ones, built in-process on the history above."""
    with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(os.environ), \
            mock.patch.object(task_eta, "LABELS", os.path.join(tmp, "none.json")), \
            mock.patch.object(task_eta, "load_predictor", return_value=corr or calibration()), \
            mock.patch.object(task_eta, "protocol_command", return_value=COMMAND):
        for name in (task_eta.CALLS_LINE_ENV, task_eta.BLOCK_ENV):
            os.environ.pop(name, None)
        os.environ.update(env or {})
        return task_eta.estimate_block("Fix the login bug in module 7", history(), current, info=info,
                                       project="-work-acme", compact=compact)


def ready(text):
    """The lines Claude copies, in order."""
    return [line for line in text.split("\n") if line.startswith("⏱ ")]


class Option(unittest.TestCase):
    """The form comes from TASK_ETA_BLOCK; anything but "compact" is the full block."""

    def form(self, value):
        with mock.patch.dict(os.environ):
            os.environ.pop(task_eta.BLOCK_ENV, None)
            if value is not None:
                os.environ[task_eta.BLOCK_ENV] = value
            return task_eta.block_form()

    def test_full_unless_asked(self):
        for value in (None, "", " ", "full"):
            self.assertEqual(self.form(value), "full", value)

    def test_compact_when_asked(self):
        for value in ("compact", "Compact", " compact\n"):
            self.assertEqual(self.form(value), "compact", value)

    def test_an_unknown_value_is_the_full_block(self):
        for value in ("short", "1", "true", "compact2", "none", "off"):
            self.assertEqual(self.form(value), "full", value)

    def test_the_block_is_full_by_default(self):
        # compact=False: a caller that says nothing gets the full block
        self.assertIs(task_eta.estimate_block.__defaults__[-1], False)
        self.assertEqual(block(False), block(False, env={task_eta.BLOCK_ENV: "compact"}))  # only the hook reads it


class CompactBlock(unittest.TestCase):
    def test_the_fixture_has_all_five_lines(self):
        lines = ready(block(True))
        self.assertEqual([task_eta.KIND_RE.search(line[line.index("~"):]).group(1) for line in lines],
                         ["quick", "medium", "long", "subagents", "subagents"])
        self.assertTrue(lines[-1].endswith("with brief subagents)"), lines[-1])
        self.assertTrue(all("likely" in line for line in lines), lines)

    def test_the_ready_lines_are_the_full_block_s(self):
        self.assertEqual(ready(block(True)), ready(block(False)))
        self.assertEqual(len(ready(block(True))), 5)

    def test_the_ready_lines_are_the_same_with_no_model_known(self):
        # No reply in the session yet: lines for each main model, and the note that says so.
        full, short = block(False, current=None), block(True, current=None)
        self.assertEqual(ready(short), ready(full))
        self.assertGreater(len({line.split(":")[0] for line in ready(short)}), 1)  # more than one model
        self.assertIn("(no reply in this session yet: use the lines of the model you are)", short)
        self.assertIn(" (times for opus-5-5 xhigh): ", short)

    def test_the_closing_command_is_the_full_block_s(self):
        full, short = block(False), block(True)
        self.assertIn("`%s elapsed`" % COMMAND, full)
        self.assertIn("`%s elapsed`" % COMMAND, short)
        self.assertEqual(re.findall(r"`([^`]* elapsed)`", short), re.findall(r"`([^`]* elapsed)`", full))
        self.assertIn("end the reply with the line it prints", short)
        self.assertIn("same command with `eta`", short)
        # What Claude runs is still what the parser leaves out of the tool calls.
        self.assertTrue(task_eta.PROTO_CMD.search(COMMAND + " elapsed"))
        self.assertTrue(task_eta.PROTO_CMD.search(COMMAND + " eta"))

    def test_it_is_under_the_size_target(self):
        full, short = block(False), block(True)
        self.assertLessEqual(len(short), SIZE_TARGET, short)
        self.assertGreater(len(full), 3 * len(short))
        words = len(short) - sum(len(line) for line in ready(short)) - len(COMMAND)
        self.assertLessEqual(words, WORDS_TARGET, short)

    def test_what_it_says(self):
        lines = block(True).split("\n")
        self.assertEqual(len(lines), 9, lines)  # what it is, the kinds, the ask, five lines, the closing command
        self.assertEqual(lines[0], "[task-eta] Time estimates from your past tasks.")
        self.assertRegex(lines[1], r"^Kinds, by tool calls planned: quick 1-3 \(~[^)]+\), medium 4-15 \(~[^)]+\), "
                                   r"long 16\+ \(~[^)]+\), with subagents \(~[^)]+\), "
                                   r"with brief subagents, each under ~10 min \(~[^)]+\)\.$")
        self.assertEqual(lines[2], "With tools, open the reply with your kind's line as is; no tools, no line:")
        self.assertTrue(lines[8].startswith("Last tool call: `"), lines[8])

    def test_the_kinds_line_gives_the_estimates_of_the_ready_lines(self):
        text = block(True)
        said = re.findall(r"\((~[^)]+)\)", text.split("\n")[1])
        self.assertEqual(said, [re.search(r": (~.+?) \(", line).group(1) for line in ready(text)])

    def test_what_it_leaves_out(self):
        full, short = block(False), block(True)
        for gone in ("held", "scaled", "as printed", "The kind you declared matched", "Most similar past requests",
                     "A similar task took", "A past request matches closely", "Real durations", "counts as 3"):
            self.assertIn(gone, full, gone)  # the fixture's full block has each of them
            self.assertNotIn(gone, short, gone)
        self.assertNotIn("login bug", short.lower())  # no past prompt text, as in the full block

    def test_the_numbers_for_the_widget_and_the_log_are_the_same(self):
        a, b = {}, {}
        block(False, info=a)
        block(True, info=b)
        self.assertTrue(a.get("kinds"))
        self.assertEqual(a["adjust"]["medium"], 0.6)  # the scaling is in the lines of both forms
        self.assertEqual(a, b)

    def test_the_tie_break_is_only_in_the_full_block(self):
        # Known difference: the advice the full block adds when the misses lean one way is left out.
        lean = calibration(misses=(2, 10))
        self.assertIn("pick the bigger", block(False, corr=lean))
        self.assertNotIn("pick the bigger", block(True, corr=lean))

    def test_the_hidden_line_experiment_still_asks(self):
        text = block(True, env={task_eta.CALLS_LINE_ENV: "1"})
        self.assertIn("[//]: # (task-eta: ~N call, A agents, L long)", text)
        self.assertEqual(ready(text), ready(block(False, env={task_eta.CALLS_LINE_ENV: "1"})))
        self.assertNotIn("[//]: #", block(True))

    def test_no_timing_data_reads_the_same(self):
        self.assertEqual(block(True, current=("opus-9-9", "high")), block(False, current=("opus-9-9", "high")))
        self.assertIn("No timing data for opus-9-9 high yet", block(True, current=("opus-9-9", "high")))


class Hook(unittest.TestCase):
    """End to end: the hook reads the option from its environment, `estimate` does not."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        projects = os.path.join(self.home, ".claude", "projects")
        os.makedirs(projects)
        start = T0
        for i in range(6):
            t = Transcript(session="s%d" % i)
            start = t.task(start + 600, "Fix the login bug on staging %d" % i, steps=5, step_s=12 + i)
            self.path = t.write(projects)
        run(["update"], self.home)

    def tearDown(self):
        remove_tmp(self.tmp)

    def hook(self, value=None):
        res = run(["hook-prompt"], self.home, extra_env={} if value is None else {task_eta.BLOCK_ENV: value},
                  stdin=json.dumps({"prompt": "fix the login bug on staging", "session_id": "n",
                                    "transcript_path": self.path}))
        self.assertEqual(res.returncode, 0, res.stderr)
        return json.loads(res.stdout)["hookSpecificOutput"]["additionalContext"]

    def test_the_hook_s_block_is_full_unless_asked(self):
        full = self.hook()
        self.assertTrue(full.startswith("[task-eta] Real durations of your past Claude Code tasks"), full)
        self.assertIn("Most similar past requests in this project", full)
        for value in ("", "full", "short", "1"):
            self.assertEqual(self.hook(value), full, value)

    def test_the_hook_s_compact_block(self):
        full, short = self.hook(), self.hook("compact")
        self.assertTrue(short.startswith("[task-eta] Time estimates from your past tasks.\n"
                                         "Kinds, by tool calls planned: "), short)
        self.assertTrue(ready(short))
        self.assertEqual(ready(short), ready(full))
        self.assertEqual(re.findall(r"`([^`]* elapsed)`", short), re.findall(r"`([^`]* elapsed)`", full))
        self.assertNotIn("Most similar past requests", short)
        self.assertLess(len(short), len(full) / 2)

    def test_the_log_of_what_was_offered_is_the_same(self):
        def offered():
            with open(os.path.join(self.home, ".claude", "task-eta", "suggestions.jsonl")) as fh:
                rec = json.loads(fh.read().splitlines()[-1])
            return {k: v for k, v in rec.items() if k != "ts"}
        self.hook()
        full = offered()
        self.hook("compact")
        self.assertEqual(offered(), full)

    def test_estimate_prints_the_full_block(self):
        res = run(["estimate", "fix the login bug on staging"], self.home, extra_env={task_eta.BLOCK_ENV: "compact"})
        self.assertIn("[task-eta] Real durations of your past Claude Code tasks", res.stdout)


if __name__ == "__main__":
    unittest.main()
