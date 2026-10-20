import importlib
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import REPO, T0, Transcript, run  # noqa: E402

sys.path.insert(0, REPO)
task_eta = importlib.import_module("task_eta")


class Lines(unittest.TestCase):
    def test_estimate_line(self):
        self.assertEqual(task_eta.parse_estimate("⏱ Estimated time with opus-5-5 high: ~3 min (likely 1 to 8 min)"),
                         (3.0, None))
        self.assertEqual(task_eta.parse_estimate("⏱ Estimated time with sonnet-5-5 medium: ~40 s")[0], 0.7)
        self.assertEqual(task_eta.parse_estimate("⏱ Estimated time with opus-5-5 max: ~1.5 h")[0], 90.0)
        self.assertEqual(task_eta.parse_estimate("no line here"), (None, None))

    def test_older_italian_lines_still_count(self):
        self.assertEqual(task_eta.parse_estimate("⏱ Tempo richiesto con opus-5-5 high: ~10 min")[0], 10.0)
        self.assertEqual(task_eta.parse_estimate("⏱ Stima: ~1,5 h")[0], 90.0)
        self.assertEqual(task_eta.parse_range("⏱ Tempo richiesto: ~10 min (probabile tra 4 e 24 min)"), [240, 1440])

    def test_range(self):
        self.assertEqual(task_eta.parse_range("⏱ Estimated time with x y: ~3 min (likely 1 to 8 min)"), [60, 480])
        self.assertEqual(task_eta.parse_range("⏱ Estimated time with x y: ~1 min (likely 40 s to 3 min)"), [40, 180])
        self.assertIsNone(task_eta.parse_range("⏱ Estimated time with x y: ~3 min"))

    def test_formats(self):
        self.assertEqual(task_eta.fmt_range(60, 480), "1 to 8 min")
        self.assertEqual(task_eta.fmt_range(40, 180), "40 s to 3 min")
        self.assertEqual(task_eta.fmt_range(20, 45), "20 to 45 s")
        self.assertEqual(task_eta.fmt_range(1200, 5400), "20 min to 1.5 h")
        self.assertEqual(task_eta.fmt_estimate(30), "~30 s")
        self.assertEqual(task_eta.fmt_estimate(200), "~3 min")
        self.assertEqual(task_eta.fmt_estimate(5400), "~1.5 h")
        self.assertEqual(task_eta.fmt_words(60), "60 seconds")
        self.assertEqual(task_eta.fmt_words(100), "2 minutes")
        # What the hook writes, the parser reads back.
        line = "⏱ Estimated time with m e: %s (likely %s)" % (task_eta.fmt_estimate(200), task_eta.fmt_range(90, 600))
        self.assertEqual(task_eta.parse_estimate(line)[0], 3.0)
        self.assertEqual(task_eta.parse_range(line), [120, 600])

    def test_categories(self):
        self.assertEqual(task_eta.guess_category({"prompt": "fix the bug in the api endpoint"}), "coding")
        self.assertEqual(task_eta.guess_category({"prompt": "write a linkedin post"}), "social")
        self.assertIsNone(task_eta.guess_category({"prompt": "hello"}))


class Parsing(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.projects = os.path.join(self.tmp.name, ".claude", "projects")

    def tearDown(self):
        self.tmp.cleanup()

    def test_one_task(self):
        t = Transcript()
        end = t.task(T0, "Fix the login bug", steps=3, step_s=20,
                     estimate="⏱ Estimated time with opus-5-5 high: ~2 min (likely 1 to 4 min)")
        tasks = task_eta.parse_transcript(t.write(self.projects))
        self.assertEqual(len(tasks), 1)
        task = tasks[0]
        self.assertAlmostEqual(task["dur_s"], end - T0, delta=1)
        self.assertEqual(task["estimate_min"], 2.0)
        self.assertEqual(task["est_range"], [60, 240])
        self.assertEqual(task["tools"], 3)
        self.assertEqual((task["model"], task["effort"]), ("opus-5-5", "high"))
        self.assertEqual(task["edit_exts"], {"py": 3})
        self.assertEqual(task["prompt"], "Fix the login bug")
        self.assertNotIn("reply", task)  # Claude's answers are not kept

    def test_wait_for_the_user_is_not_counted(self):
        t = Transcript()
        t.prompt(T0, "Plan the release")
        t.tool(T0 + 5, "AskUserQuestion", {"questions": []}, T0 + 605)  # the user answers 10 min later
        t.say(T0 + 615, "Done.", end=True)
        t.stop(T0 + 616)
        task = task_eta.parse_transcript(t.write(self.projects))[0]
        self.assertAlmostEqual(task["dur_s"], 16, delta=1)
        self.assertAlmostEqual(task["wait_s"], 600, delta=1)

    def test_notifications_are_not_new_tasks(self):
        t = Transcript()
        t.task(T0, "Run the tests", steps=1)
        t.prompt(T0 + 100, "<task-notification>done</task-notification>", origin="task-notification")
        t.say(T0 + 105, "All green.", end=True)
        t.stop(T0 + 106)
        tasks = task_eta.parse_transcript(t.write(self.projects))
        self.assertEqual(len(tasks), 1)

    def test_headless_runs_are_flagged(self):
        t = Transcript()
        t.prompt(T0, "say hi", origin=None, entrypoint="sdk-cli")
        t.tool(T0 + 2, "Bash", {"command": "echo hi"}, T0 + 3)
        t.say(T0 + 4, "hi", end=True)
        task = task_eta.parse_transcript(t.write(self.projects))[0]
        self.assertTrue(task["headless"])
        self.assertEqual(task_eta.range_group(False, task), "test")


class Commands(unittest.TestCase):
    """The script as the hooks run it, against a temporary home."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        projects = os.path.join(self.home, ".claude", "projects")
        start = T0
        for i, prompt in enumerate(["Fix the login bug on staging", "Fix the signup bug on staging",
                                    "Add a dark mode toggle", "Refactor the api client",
                                    "Write tests for the parser", "Fix the logout bug on staging",
                                    "Update the build script", "Fix the payment form bug"]):
            t = Transcript(session="s%d" % i)
            start = t.task(start + 600, prompt, steps=5, step_s=12 + i)
            self.last_path = t.write(projects)

    def tearDown(self):
        self.tmp.cleanup()

    def test_update_report_and_hook(self):
        out = run(["update"], self.home)
        self.assertIn("8 tasks in the index", out.stdout)
        report = run(["report"], self.home).stdout
        self.assertIn("Tasks measured: 8", report)
        run(["calibrate"], self.home)
        hook_in = json.dumps({"prompt": "fix the cart bug on staging", "session_id": "new",
                              "transcript_path": self.last_path, "cwd": "/work/acme"})
        res = run(["hook-prompt"], self.home, stdin=hook_in)
        self.assertEqual(res.returncode, 0, res.stderr)
        block = json.loads(res.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("[task-eta]", block)
        self.assertIn("⏱ Estimated time with opus-5-5 high: ~", block)
        self.assertIn("elapsed", block)
        self.assertIn("Fix the login bug on staging", block)  # similar past request, from this home only
        live = os.path.join(self.home, ".claude", "task-eta", "live", "new.json")
        self.assertTrue(os.path.exists(live))

    def test_notifications_get_no_block(self):
        run(["update"], self.home)
        res = run(["hook-prompt"], self.home, stdin=json.dumps({"prompt": "<task-notification>x", "session_id": "a"}))
        self.assertEqual(res.stdout, "")

    def test_hook_survives_bad_input(self):
        for stdin in ("", "not json", "[]"):
            res = run(["hook-prompt"], self.home, stdin=stdin)
            self.assertEqual(res.returncode, 0, res.stderr)

    def test_history_since(self):
        cfg = os.path.join(self.home, ".claude", "task-eta")
        os.makedirs(cfg, exist_ok=True)
        with open(os.path.join(cfg, "config.json"), "w") as fh:
            json.dump({"since": T0 + 600 * 5}, fh)
        out = run(["update"], self.home)
        self.assertIn("tasks in the index", out.stdout)
        with open(os.path.join(cfg, "index.json")) as fh:
            starts = [t["start_ts"] for t in json.load(fh)["tasks"].values()]
        self.assertTrue(starts and min(starts) >= T0 + 600 * 5)

    def test_session_id_cannot_escape_the_live_folder(self):
        run(["update"], self.home)
        evil = json.dumps({"prompt": "fix it", "session_id": "../../evil", "transcript_path": self.last_path})
        run(["hook-prompt"], self.home, stdin=evil)
        self.assertFalse(os.path.exists(os.path.join(self.home, ".claude", "evil.json")))
        live = os.listdir(os.path.join(self.home, ".claude", "task-eta", "live"))
        self.assertTrue(all("/" not in name for name in live))


if __name__ == "__main__":
    unittest.main()
