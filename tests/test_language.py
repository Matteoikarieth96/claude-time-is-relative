"""The language of what the user reads: English by default, Italian when chosen in TaskETA (or with
`task_eta.py language it`), from ~/.claude/task-eta/language.json. The lines meant for Claude stay English."""
import contextlib
import importlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import REPO, T0  # noqa: E402

sys.path.insert(0, REPO)
task_eta = importlib.import_module("task_eta")

EN = {"diamante": "Diamond", "smeraldo": "Emerald", "oro": "Gold Ingot", "ferro": "Iron Ingot", "carbone": "Coal",
      "ragnatela": "Cobweb", "patata": "Poisonous Potato", "polvere": "Gunpowder", "occhio": "Spider Eye",
      "marcia": "Rotten Flesh"}


def task(i, real, est_min=5.0):
    return {"start_ts": T0 + i * 60, "dur_s": real, "estimate_min": est_min, "est_range": [200, 450]}


class Language(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.saved = (task_eta.LANG_FILE, task_eta.DATA_DIR, task_eta.MINE_FILE, task_eta._lang)
        task_eta.DATA_DIR = self.tmp
        task_eta.LANG_FILE = os.path.join(self.tmp, "language.json")
        task_eta.MINE_FILE = os.path.join(self.tmp, "miniera.json")
        task_eta._lang = None

    def tearDown(self):
        task_eta.LANG_FILE, task_eta.DATA_DIR, task_eta.MINE_FILE, task_eta._lang = self.saved
        shutil.rmtree(self.tmp, ignore_errors=True)

    def choose(self, data):
        with open(task_eta.LANG_FILE, "w", encoding="utf-8") as fh:
            fh.write(data if isinstance(data, str) else json.dumps(data))
        task_eta._lang = None

    def run_cmd(self, fn, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = fn(*args)
        return code, out.getvalue()

    def test_english_without_a_choice(self):
        self.assertEqual(task_eta.ui_lang(), "en")
        self.assertEqual(task_eta.tr("running", "in corso"), "running")

    def test_the_resolved_language_of_the_app(self):
        self.choose({"choice": "system", "language": "it"})
        self.assertEqual(task_eta.ui_lang(), "it")
        self.assertEqual(task_eta.tr("running", "in corso"), "in corso")

    def test_broken_or_unknown_is_english(self):
        for data in ("{oops", "[1, 2]", {"choice": "fr", "language": "fr"}, {"choice": "it"}):
            self.choose(data)
            self.assertEqual(task_eta.ui_lang(), "en", data)

    def test_the_ten_finds_in_both_languages(self):
        self.assertEqual({k: task_eta.mine_name(k) for k in EN}, EN)
        self.choose({"choice": "it", "language": "it"})
        self.assertEqual({k: task_eta.mine_name(k) for k in EN}, task_eta.MINE_NAMES)

    def test_the_app_uses_the_same_names(self):
        """Miniera.swift shows the same ten finds and five pickaxes in English."""
        with open(os.path.join(REPO, "widget", "Sources", "Miniera.swift"), encoding="utf-8") as fh:
            swift = fh.read()
        for name in list(EN.values()) + list(task_eta.PICKAXES_EN.values()):
            self.assertIn('"%s"' % name, swift)

    def test_pickaxe_needs_in_english(self):
        need = [task_eta.pickaxe_need(p) for p in task_eta.PICKAXES[1:]]
        self.assertEqual(need, ["1 Block of Diamond", "3 Blocks of Diamond", "1 Surry's Beacon lit",
                                "3 Surry's Beacons lit"])

    def test_the_line_for_claude_quotes_the_users_words(self):
        task_eta.mine_update([task(i, 300) for i in range(9)])   # the Stone Pickaxe is earned
        line = task_eta.mine_block_line()
        self.assertIn("stone pickaxe", line)
        self.assertIn("“take the pickaxe”", line)
        self.assertIn("piccone su", line)
        self.choose({"choice": "it", "language": "it"})
        line = task_eta.mine_block_line()
        self.assertIn("stone pickaxe", line)                      # still English: it is for Claude
        self.assertIn("«prendi il piccone»", line)

    def test_the_pickaxe_command_speaks_the_language(self):
        idx = {"tasks": {str(i): task(i, 300) for i in range(9)}}
        old = task_eta.load_index
        task_eta.load_index = lambda *a, **k: idx
        try:
            _, out = self.run_cmd(task_eta.cmd_piccone, [])
            self.assertIn("Wooden Pickaxe. 9 diamonds, 1 Block of Diamond, 0 beacons lit.", out)
            self.assertIn("The next one, the Stone Pickaxe, wants 1 Block of Diamond: ready", out)
            _, out = self.run_cmd(task_eta.cmd_piccone, ["up"])  # "up" works like "su"
            self.assertIn("Took the Stone Pickaxe.", out)
            _, out = self.run_cmd(task_eta.cmd_piccone, ["up"])  # iron wants 3 blocks
            self.assertIn("Not yet: the Iron Pickaxe needs 3 Blocks of Diamond.", out)
            self.assertEqual(task_eta.mine_state()["piccone"], "pietra")
            self.choose({"choice": "it", "language": "it"})
            _, out = self.run_cmd(task_eta.cmd_piccone, [])
            self.assertIn("Piccone di pietra. 9 diamanti, 1 blocco di diamante, 0 fari accesi.", out)
        finally:
            task_eta.load_index = old
        self.assertTrue(task_eta.PROTO_CMD.search("python3 ~/x/task_eta.py pickaxe up"))

    def test_the_language_command(self):
        code, out = self.run_cmd(task_eta.cmd_language, ["it"])
        self.assertEqual(code, 0)
        with open(task_eta.LANG_FILE, encoding="utf-8") as fh:
            self.assertEqual(json.load(fh), {"choice": "it", "language": "it"})
        self.assertIn("Lingua: Italiano", out)
        code, out = self.run_cmd(task_eta.cmd_language, ["en"])
        self.assertEqual(task_eta.ui_lang(), "en")
        self.assertIn("Language: English (chosen: en)", out)
        code, _ = self.run_cmd(task_eta.cmd_language, ["system"])
        with open(task_eta.LANG_FILE, encoding="utf-8") as fh:
            saved = json.load(fh)
        self.assertEqual(saved["choice"], "system")
        self.assertIn(saved["language"], ("en", "it"))
        code, _ = self.run_cmd(task_eta.cmd_language, ["fr"])
        self.assertEqual(code, 1)
        with open(task_eta.LANG_FILE, encoding="utf-8") as fh:
            self.assertEqual(json.load(fh)["choice"], "system")  # a wrong word changes nothing

    def test_the_week_line_never_reads_the_language(self):
        """The block for Claude is English: only the pickaxe line, while one waits, reads the file (cached)."""
        self.choose("{oops")
        task_eta.mine_week_line({"settimane": [{"dal": "2026-10-19", "colpi": 20, "buoni": 17}]})
        self.assertIsNone(task_eta._lang)


if __name__ == "__main__":
    unittest.main()
