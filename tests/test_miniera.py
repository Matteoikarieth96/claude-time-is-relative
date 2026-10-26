"""La miniera in the hook (Miniera.swift in the app): the find of each estimate, judged as the app
judges it, the blocks and beacons, and the pickaxe that waits for the user's yes."""
import importlib
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


def task(i, real, est_min=5.0, rng=(200, 450), day=0, **extra):
    t = {"start_ts": T0 + day * 86400 + i * 60, "dur_s": real, "estimate_min": est_min, "est_range": list(rng)}
    t.update(extra)
    return t


class Finds(unittest.TestCase):
    """The same thresholds as MineTest in Miniera.swift."""

    def find(self, real, rng=(200, 450)):
        return task_eta.mine_find(real, 300, rng)

    def test_the_ten_finds(self):
        self.assertEqual([self.find(r) for r in (300, 315, 285)], ["diamante"] * 3)
        self.assertEqual(self.find(324), "smeraldo")
        self.assertEqual(self.find(420), "oro")
        self.assertEqual(task_eta.mine_find(420, 300, (250, 400)), "ferro")
        self.assertEqual((self.find(500), self.find(160)), ("carbone", "carbone"))
        self.assertEqual((self.find(800), self.find(110)), ("ragnatela", "ragnatela"))
        self.assertEqual((self.find(1400), self.find(70)), ("patata", "patata"))
        self.assertEqual((self.find(2000), self.find(50)), ("polvere", "polvere"))
        self.assertEqual((self.find(2900), self.find(31)), ("occhio", "occhio"))
        self.assertEqual((self.find(3100), self.find(25)), ("marcia", "marcia"))

    def test_no_range_is_seven_tenths_to_one_and_a_half(self):
        self.assertEqual(task_eta.mine_find(420, 300, None), "oro")


class Progress(unittest.TestCase):
    def test_blocks_and_a_beacon(self):
        week = [task(i, 300) for i in range(18)] + [task(18, 3000), task(19, 3000)]   # 18 of 20 good
        self.assertEqual(task_eta.mine_progress(week), (18, 2, 1))

    def test_no_beacon_under_80_or_20(self):
        self.assertEqual(task_eta.mine_progress([task(i, 300) for i in range(19)])[2], 0)
        week = [task(i, 300) for i in range(15)] + [task(15 + i, 3000) for i in range(5)]   # 75%
        self.assertEqual(task_eta.mine_progress(week)[2], 0)

    def test_headless_and_no_estimate_are_left_out(self):
        self.assertEqual(task_eta.mine_progress([task(0, 300, headless=True), task(1, 300, est_min=None)]), (0, 0, 0))


class Pickaxe(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.old = task_eta.MINE_FILE
        task_eta.MINE_FILE = os.path.join(self.tmp, "miniera.json")
        self.old_lang, task_eta._lang = task_eta._lang, "it"   # these read the Italian words (test_language: English)

    def tearDown(self):
        task_eta.MINE_FILE = self.old
        task_eta._lang = self.old_lang
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_starts_in_wood_and_waits_for_a_yes(self):
        self.assertEqual(task_eta.mine_state()["piccone"], "legno")
        self.assertIsNone(task_eta.mine_block_line())
        state, nxt, earned = task_eta.mine_update([task(i, 300) for i in range(9)])   # 1 block
        self.assertEqual((nxt[0], earned, state["pronto"]), ("pietra", True, "pietra"))
        self.assertEqual(task_eta.mine_state()["piccone"], "legno")                 # not taken by itself
        line = task_eta.mine_block_line()
        self.assertIn("stone pickaxe", line)                # the line is for Claude: English
        self.assertIn("piccone su", line)
        self.assertIn("prendi il piccone", line)          # asked for by name, never a bare yes
        self.assertIn("never counts", line)

    def test_not_earned_and_the_last_one(self):
        state, nxt, earned = task_eta.mine_update([task(0, 300)])
        self.assertEqual((nxt[0], earned, state["pronto"]), ("pietra", False, None))
        with open(task_eta.MINE_FILE, "w") as fh:
            json.dump({"piccone": "diamante"}, fh)
        self.assertEqual(task_eta.pickaxe_next(task_eta.mine_state(), 99, 99), (None, False))

    def test_needs_in_words(self):
        self.assertEqual(task_eta.pickaxe_need(task_eta.PICKAXES[1]), "1 blocco di diamante")
        self.assertEqual(task_eta.pickaxe_need(task_eta.PICKAXES[2]), "3 blocchi di diamante")
        self.assertEqual(task_eta.pickaxe_need(task_eta.PICKAXES[3]), "1 Faro di Surry acceso")
        self.assertEqual(task_eta.pickaxe_need(task_eta.PICKAXES[4]), "3 Fari di Surry accesi")

    def test_take_only_once_earned(self):
        idx = {"tasks": {str(i): task(i, 300) for i in range(9)}}
        old = task_eta.load_index
        task_eta.load_index = lambda *a, **k: idx
        try:
            task_eta.cmd_piccone(["su"])
            self.assertEqual(task_eta.mine_state()["piccone"], "pietra")
            task_eta.cmd_piccone(["su"])                      # iron wants 3 blocks
            self.assertEqual(task_eta.mine_state()["piccone"], "pietra")
            before = open(task_eta.MINE_FILE).read()
            task_eta.cmd_piccone([])                          # the status writes nothing
            self.assertEqual(open(task_eta.MINE_FILE).read(), before)
        finally:
            task_eta.load_index = old

    def test_the_pickaxe_command_is_protocol_not_work(self):
        self.assertTrue(task_eta.PROTO_CMD.search("python3 ~/x/task_eta.py piccone su"))

    def test_the_week_line_for_claude(self):
        from datetime import date
        self.assertIsNone(task_eta.mine_week_line({"settimane": []}))
        state = {"settimane": [{"dal": "2026-10-12", "colpi": 50, "buoni": 29}, {"dal": "2026-10-19", "colpi": 216, "buoni": 141}]}
        line = task_eta.mine_week_line(state, today=date(2026, 10, 25))
        self.assertIn("this week 65%", line)
        self.assertIn("last week 58%", line)
        self.assertIn("best week 65%", line)
        self.assertIn("80% good", line)
        self.assertIn("no stroke yet this week", task_eta.mine_week_line(state, today=date(2026, 10, 27)))

    def test_weeks_from_monday(self):
        weeks, diamonds = task_eta.mine_weeks([task(i, 300) for i in range(3)])
        self.assertEqual((len(weeks), weeks[0][1], weeks[0][2], diamonds), (1, 3, 3, 3))
        self.assertEqual(weeks[0][0].weekday(), 0)

    def test_a_broken_file_reads_as_wood(self):
        with open(task_eta.MINE_FILE, "w") as fh:
            fh.write("{oops")
        self.assertEqual(task_eta.mine_state()["piccone"], "legno")


if __name__ == "__main__":
    unittest.main()
