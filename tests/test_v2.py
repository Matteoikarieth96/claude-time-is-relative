"""What the v2 estimator added: kinds of work, secret redaction, background work credited to the task
that launched it, turns ended by wrap_up, a locked index with a daily copy, per-kind calibration."""
import importlib
import json
import os
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import REPO, T0, Transcript, iso, run  # noqa: E402

sys.path.insert(0, REPO)
task_eta = importlib.import_module("task_eta")

BODY = "A1b2C3d4E5f6G7h8J9k0"
# Built from pieces, so no key-like string sits in the source for scanners to flag.
FAKE_KEYS = [p + BODY for p in ("sk-", "sk-" + "ant-api03-", "sk-" + "proj-", "xai-", "gh" + "p_", "gh" + "o_",
                                "github" + "_pat_", "AK" + "IA", "xo" + "xb-", "pk" + "_live_", "pk" + "_drip_",
                                "st" + "k_", "pro" + "api_")]
PEM = "-----BEGIN " + "RSA PRIVATE KEY-----\nMIIEow" + BODY + "\n-----END " + "RSA PRIVATE KEY-----"


class Redaction(unittest.TestCase):
    def test_known_prefixes_and_pem_blocks(self):
        for key in FAKE_KEYS + [PEM]:
            text = "deploy with %s now" % key
            out = task_eta.redact(text)
            self.assertNotIn(BODY, out, key[:12])
            self.assertIn("[secret]", out)
            self.assertTrue(out.startswith("deploy with ") and out.endswith(" now"), out)
            self.assertEqual(task_eta.redact(out), out)  # idempotent
        self.assertNotIn(BODY, task_eta.redact(task_eta.clean_prompt("key: " + PEM.replace("\n", "\r\n"))))

    def test_ordinary_text_is_kept(self):
        for text in ("fix the login bug in api/v2/users", "use claude-opus-5-5 at xhigh",
                     "internationalization-and-localization-work", "see task_eta-2026-10-20-pre-review.py"):
            self.assertEqual(task_eta.redact(text), text)

    def test_keywords_and_urls(self):
        out = task_eta.redact("password: hunter2024 and https://bob:s3cretpass" + "@db.example.com/x")
        self.assertNotIn("hunter2024", out)
        self.assertNotIn("s3cretpass", out)

    def test_hostile_text_stays_fast(self):
        for text in ("-----BEGIN A-----" * 6000, "a1" * 50000, "sk-" * 30000, "password: " * 10000 + "1"):
            start = time.time()
            task_eta.redact(text)
            self.assertLess(time.time() - start, 1.0, text[:20])


class Parsing(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.projects = os.path.join(self.tmp.name, ".claude", "projects")

    def tearDown(self):
        self.tmp.cleanup()

    def test_a_background_agent_belongs_to_the_task_that_launched_it(self):
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
        t.records.append({"type": "user", "timestamp": iso(T0 + 400), "origin": {"kind": "task-notification"},
                          "message": {"role": "user", "content": "<task-notification><tool-use-id>%s</tool-use-id>"
                                      "<status>completed</status></task-notification>" % tid}})
        t.say(T0 + 405, "The research is done: here it is.", end=True)
        t.stop(T0 + 410)
        first, second = task_eta.parse_transcript(t.write(self.projects))
        self.assertAlmostEqual(first["dur_s"], 410, delta=2)  # ran until its agent reported and was handled
        self.assertGreater(first["bg_tail_s"], 0)
        self.assertAlmostEqual(second["dur_s"], 8, delta=2)   # the wait and the handling are not the typo's
        self.assertNotIn("pending_bg", first)

    def test_an_agent_still_out_keeps_its_task_unfinished(self):
        t = Transcript()
        t.prompt(T0, "Research three note apps")
        t.tool(T0 + 2, "Agent", {"run_in_background": True}, T0 + 3, result="Async agent launched. agentId: abcdef12")
        t.say(T0 + 5, "Started.", end=True)
        t.stop(T0 + 6)
        task = task_eta.parse_transcript(t.write(self.projects))[0]
        self.assertEqual(task["pending_bg"], 1)
        self.assertEqual(task_eta.finished_tasks({"tasks": {"k": dict(task, end_ts=time.time())}}), [])

    def test_wrap_up_ends_the_turn(self):
        t = Transcript()
        t.prompt(T0, "Tidy the notes")
        t.tool(T0 + 2, "Edit", {"file_path": "/work/acme/notes.md"}, T0 + 10)
        t.tool(T0 + 12, "mcp__ccd_turn__wrap_up", {}, T0 + 13)
        t.prompt(T0 + 3000, "Next thing")
        t.say(T0 + 3002, "Sure.", end=True)
        with mock.patch.object(task_eta, "TERMINAL_TOOLS", {"mcp__ccd_turn__wrap_up"}):
            task = task_eta.parse_transcript(t.write(self.projects))[0]
        self.assertFalse(task["open"])
        self.assertAlmostEqual(task["dur_s"], 13, delta=1)

    def test_the_estimate_protocol_is_not_work(self):
        t = Transcript()
        t.prompt(T0, "What time is it in Tokyo?")
        t.tool(T0 + 2, "Bash", {"command": "python3 '/x y/task_eta.py' elapsed"}, T0 + 3)
        t.say(T0 + 4, "It is 9 pm.", end=True)
        task = task_eta.parse_transcript(t.write(self.projects))[0]
        self.assertEqual((task["tools"], task["proto"], task_eta.task_kind(task)), (1, 1, "text"))
        self.assertFalse(task_eta.is_work(task))


class Index(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.projects = os.path.join(self.home, ".claude", "projects")
        self.data = os.path.join(self.home, ".claude", "task-eta")
        self.paths = []
        for i in range(6):
            t = Transcript(session="s%d" % i)
            t.task(T0 + i * 1000, "Fix bug number %d" % i, steps=2 + i)
            self.paths.append(t.write(self.projects))
        run(["update"], self.home)

    def tearDown(self):
        self.tmp.cleanup()

    def load(self):
        with open(os.path.join(self.data, "index.json")) as fh:
            return json.load(fh)

    def test_a_broken_index_is_moved_aside_and_the_daily_copy_stands_in(self):
        self.assertTrue(os.path.exists(os.path.join(self.data, "index.json.bak")))
        os.remove(self.paths[0])  # its task now lives only in the index and its daily copy
        with open(os.path.join(self.data, "index.json"), "w") as fh:
            fh.write("{ broken")
        run(["update"], self.home)
        self.assertTrue(any(n.startswith("index.json.unreadable-") for n in os.listdir(self.data)))
        self.assertIn("Fix bug number 0", [t["prompt"] for t in self.load()["tasks"].values()])

    def test_a_missing_index_comes_back_from_the_daily_copy(self):
        os.remove(self.paths[0])
        os.remove(os.path.join(self.data, "index.json"))
        run(["update"], self.home)
        self.assertIn("Fix bug number 0", [t["prompt"] for t in self.load()["tasks"].values()])

    def test_an_older_index_is_scrubbed_once_and_reparsed(self):
        idx = self.load()
        key = next(iter(idx["tasks"]))
        idx["tasks"][key]["prompt"] = "use " + FAKE_KEYS[1]
        idx["tasks"][key]["reply"] = "Claude's whole answer"
        idx.update(redact=1, parser=3)
        with open(os.path.join(self.data, "index.json"), "w") as fh:
            json.dump(idx, fh)
        run(["update"], self.home)
        idx = self.load()
        self.assertEqual((idx["redact"], idx["parser"]), (task_eta.REDACT_VERSION, task_eta.PARSER_VERSION))
        text = json.dumps(idx)
        self.assertNotIn(BODY, text)
        self.assertNotIn("Claude's whole answer", text)


class Estimates(unittest.TestCase):
    """30 tasks: quick ones (2 tool calls) and medium ones (8)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        projects = os.path.join(self.home, ".claude", "projects")
        start = T0
        for i in range(30):
            t = Transcript(session="s%d" % i)
            quick = i % 2 == 0
            start = t.task(start + 600, ("Rename a variable %d" if quick else "Refactor the parser module %d") % i,
                           steps=2 if quick else 8, step_s=5 if quick else 20 + i)
            self.last = t.write(projects)
        run(["update"], self.home)

    def tearDown(self):
        self.tmp.cleanup()

    def test_calibration_by_kind(self):
        res = run(["calibrate"], self.home)
        data = json.loads(res.stdout)
        self.assertEqual(data["version"], 2)
        self.assertEqual(sorted(data["kinds"]), ["medium", "quick"])
        self.assertLessEqual(data["kinds"]["quick"]["lo"], 1.0)
        self.assertGreaterEqual(data["kinds"]["quick"]["hi"], 1.0)

    def test_block_has_a_line_per_kind_in_order(self):
        run(["calibrate"], self.home)
        res = run(["hook-prompt"], self.home, stdin=json.dumps({"prompt": "refactor the parser",
                                                                 "session_id": "n", "transcript_path": self.last}))
        block = json.loads(res.stdout)["hookSpecificOutput"]["additionalContext"]
        lines = [l for l in block.splitlines() if l.startswith("⏱ Estimated time with opus-5-5 high:")]
        self.assertEqual([task_eta.parse_kind(l) for l in lines], ["quick", "medium", "long", "agents"])
        values = [task_eta.parse_estimate(l)[0] for l in lines]
        self.assertEqual(values, sorted(values))
        self.assertIn("likely", lines[0])
        with open(os.path.join(self.home, ".claude", "task-eta", "live", "n.json")) as fh:
            live = json.load(fh)
        self.assertEqual(sorted(live["kinds"]), ["agents", "long", "medium", "quick"])

    def test_stop_hook_reports_declared_and_real_kind(self):
        t = Transcript(session="k")
        t.task(T0 + 40000, "Refactor the parser again", steps=8,
               estimate="⏱ Estimated time with opus-5-5 high: ~1 min (likely 30 s to 2 min, quick)")
        path = t.write(os.path.join(self.home, ".claude", "projects"))
        res = run(["hook-stop"], self.home, stdin=json.dumps({"session_id": "k", "transcript_path": path}))
        self.assertIn("kind quick, actual medium", json.loads(res.stdout)["systemMessage"])

    def test_elapsed_reads_the_session_and_checks_the_range(self):
        t = Transcript(session="e")
        t.task(T0 + 40000, "Refactor the parser once more", steps=3,
               estimate="⏱ Estimated time with opus-5-5 high: ~1 min (likely 30 s to 2 min, quick)")
        t.write(os.path.join(self.home, ".claude", "projects"))
        out = run(["elapsed"], self.home, extra_env={"CLAUDE_CODE_SESSION_ID": "e"}).stdout
        self.assertTrue(out.startswith("⏱ Actual time: ~"), out)
        self.assertIn("likely 30 s to 2 min:", out)


if __name__ == "__main__":
    unittest.main()
