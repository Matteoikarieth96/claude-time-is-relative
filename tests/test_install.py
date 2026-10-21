import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import INSTALL, run  # noqa: E402

OTHER = {"permissions": {"allow": ["Bash(ls:*)"]},
         "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo mine"}]}]}}
YES = ("--hooks", "yes", "--history", "no", "--claude-md", "yes", "--widget", "no")
NO_EXTRAS = ("--hooks", "yes", "--history", "no", "--claude-md", "no", "--widget", "no")


class Installer(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.claude = os.path.join(self.home, ".claude")
        os.makedirs(os.path.join(self.claude, "projects"))
        self.settings = os.path.join(self.claude, "settings.json")
        self.md = os.path.join(self.claude, "CLAUDE.md")
        self.write_settings(OTHER)
        with open(self.md, "w") as fh:
            fh.write("# My rules\n\n- be brief\n")

    def tearDown(self):
        self.tmp.cleanup()

    def write_settings(self, data):
        with open(self.settings, "w") as fh:
            json.dump(data, fh) if not isinstance(data, str) else fh.write(data)

    def install(self, *args, ok=True):
        res = run(list(args), self.home, stdin="", script=INSTALL)
        if ok:
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        return res

    def load(self):
        with open(self.settings) as fh:
            return json.load(fh)

    def commands(self, event):
        return [h["command"] for g in self.load()["hooks"].get(event, []) for h in g["hooks"]]

    def test_install_keeps_other_settings_and_is_idempotent(self):
        self.install(*YES)
        first = self.load()
        self.assertEqual(first["permissions"], OTHER["permissions"])
        stop = self.commands("Stop")
        self.assertIn("echo mine", stop)
        self.assertEqual(sum("task_eta.py" in c for c in stop), 1)
        self.assertIn("UserPromptSubmit", first["hooks"])
        self.assertNotIn("PostToolUse", first["hooks"])  # widget hooks only with the widget
        self.install(*YES)
        self.assertEqual(self.load(), first)
        with open(self.md) as fh:
            md = fh.read()
        self.assertTrue(md.startswith("# My rules\n\n- be brief\n"))
        self.assertEqual(md.count("<!-- task-eta:start -->"), 1)
        self.assertTrue(os.path.islink(os.path.join(self.claude, "skills", "task-eta")))

    def test_uninstall_restores(self):
        self.install(*YES)
        self.install("--uninstall")
        self.assertEqual(self.load(), OTHER)
        with open(self.md) as fh:
            self.assertEqual(fh.read(), "# My rules\n\n- be brief\n")
        self.assertFalse(os.path.lexists(os.path.join(self.claude, "skills", "task-eta")))

    def test_nothing_without_a_yes(self):
        out = self.install().stdout
        self.assertIn("Nothing installed", out)
        self.assertEqual(self.load(), OTHER)
        self.assertFalse(os.path.lexists(os.path.join(self.claude, "skills", "task-eta")))
        self.assertFalse(os.path.exists(os.path.join(self.claude, "task-eta")))

    def test_unanswered_extras_mean_no(self):
        out = self.install("--hooks", "yes").stdout
        self.assertIn("no terminal to ask in", out)
        with open(self.md) as fh:
            self.assertNotIn("task-eta", fh.read())
        self.assertTrue(os.path.exists(os.path.join(self.claude, "task-eta", "config.json")))

    def test_dry_run_changes_nothing(self):
        before = sorted(os.listdir(self.claude))
        self.install("--dry-run", "--hooks", "yes", "--history", "yes", "--claude-md", "yes", "--widget", "no")
        self.assertEqual(sorted(os.listdir(self.claude)), before)
        self.assertEqual(self.load(), OTHER)

    def test_bad_settings_are_never_touched(self):
        for bad in ("{ not json", '{"hooks": "x"}', '{"hooks": {"Stop": {"a": 1}}}', "[1, 2]"):
            self.write_settings(bad)
            res = self.install(*NO_EXTRAS, ok=False)
            self.assertNotEqual(res.returncode, 0, bad)
            with open(self.settings) as fh:
                self.assertEqual(fh.read(), bad)
            self.assertFalse(os.path.lexists(os.path.join(self.claude, "skills", "task-eta")), bad)

    def test_unbalanced_markers_are_refused(self):
        text = "# Rules\n<!-- task-eta:start -->\n- deploy rules I wrote\n"
        with open(self.md, "w") as fh:
            fh.write(text)
        res = self.install(*YES, ok=False)
        self.assertNotEqual(res.returncode, 0)
        with open(self.md) as fh:
            self.assertEqual(fh.read(), text)
        self.assertEqual(self.load(), OTHER)

    def test_links_are_followed_not_replaced(self):
        target = os.path.join(self.home, "dotfiles", "settings.json")
        os.makedirs(os.path.dirname(target))
        os.replace(self.settings, target)
        os.symlink(target, self.settings)
        self.install(*NO_EXTRAS)
        self.assertTrue(os.path.islink(self.settings))
        with open(target) as fh:
            self.assertIn("UserPromptSubmit", json.load(fh)["hooks"])

    def test_backups_are_never_overwritten(self):
        for _ in range(3):
            self.install(*YES)
            self.install("--uninstall")
        folder = os.path.join(self.claude, "task-eta", "backups")
        backups = [n for n in os.listdir(folder) if n.startswith("CLAUDE.md.")]
        self.assertEqual(len(backups), 6)

    def test_only_its_own_hooks_are_removed(self):
        others = ["python3 ~/bin/jira_task_eta.py sync",
                  "notify.sh && python3 /opt/x/task_eta.py hook-stop",
                  "rsync -a ~/.claude/task-eta/live/ /backup/"]
        legacy = 'PATH="/usr/bin:$PATH" python3 "$HOME/tools/task-eta-skill/task_eta.py" hook-stop 2>/dev/null || true'
        self.write_settings({"hooks": {"Stop": [{"hooks": [{"type": "command", "command": c} for c in others + [legacy]]}]}})
        self.install(*NO_EXTRAS)
        stop = self.commands("Stop")
        self.assertNotIn(legacy, stop)  # an older hand-made task-eta hook is replaced
        for c in others:
            self.assertIn(c, stop)
        self.install("--uninstall")
        self.assertEqual(self.commands("Stop"), others)

    def test_a_real_skill_folder_is_left_alone(self):
        folder = os.path.join(self.claude, "skills", "task-eta")
        os.makedirs(folder)
        out = self.install(*NO_EXTRAS).stdout
        self.assertIn("left alone", out)
        self.assertTrue(os.path.isdir(folder) and not os.path.islink(folder))

    def test_hook_commands_are_quoted(self):
        self.install(*NO_EXTRAS, "--python", "/opt/my python/bin/python3")
        cmd = self.commands("UserPromptSubmit")[0]
        self.assertTrue(cmd.startswith("'/opt/my python/bin/python3' "), cmd)

    def test_purge_deletes_only_its_own_files(self):
        self.install(*NO_EXTRAS)
        data = os.path.join(self.claude, "task-eta")
        with open(os.path.join(data, "index.json"), "w") as fh:
            json.dump({"version": 1, "files": {}, "tasks": {}}, fh)
        with open(os.path.join(data, "my-notes.txt"), "w") as fh:
            fh.write("keep me")
        self.install("--uninstall", "--purge", "--yes-purge")
        self.assertFalse(os.path.exists(os.path.join(data, "index.json")))
        self.assertTrue(os.path.exists(os.path.join(data, "my-notes.txt")))

    def test_purge_never_touches_a_folder_set_by_the_environment(self):
        invoices = os.path.join(self.home, "Documents", "invoices")
        os.makedirs(invoices)
        for name, body in (("2026-q3.json", '{"total": 1}'), ("notes.input", '{"a": 1}'), ("draft.tmp", "x"),
                           ("photo.json", '{"version": 1}')):
            with open(os.path.join(invoices, name), "w") as fh:
                fh.write(body)
        res = run(["--uninstall", "--purge", "--yes-purge"], self.home, stdin="", script=INSTALL,
                  extra_env={"TASK_ETA_LIVE_DIR": invoices})
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(sorted(os.listdir(invoices)), ["2026-q3.json", "draft.tmp", "notes.input", "photo.json"])

    def test_uninstall_leaves_a_read_only_claude_md(self):
        self.install(*YES)
        os.chmod(self.md, 0o444)
        try:
            self.install("--uninstall")
            with open(self.md) as fh:
                self.assertIn("<!-- task-eta:start -->", fh.read())
        finally:
            os.chmod(self.md, 0o644)

    def test_read_only_claude_folder_changes_nothing(self):
        os.chmod(self.claude, 0o555)
        try:
            res = self.install(*NO_EXTRAS, ok=False)
            self.assertNotEqual(res.returncode, 0)
            self.assertNotIn("Traceback", res.stderr)
        finally:
            os.chmod(self.claude, 0o755)
        self.assertEqual(self.load(), OTHER)
        self.assertFalse(os.path.lexists(os.path.join(self.claude, "skills")))

if __name__ == "__main__":
    unittest.main()
