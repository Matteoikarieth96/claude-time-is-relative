"""Guards the published files against personal data: email addresses, home paths, keys."""
import os
import re
import struct
import subprocess
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
ALLOWED_EMAIL = re.compile(r"@(example\.(com|org)|users\.noreply\.github\.com)$")
HOME_PATH = re.compile(r"/(Users|home)/(?!runner\b|me\b|you\b|name\b)[A-Za-z][\w.-]+", re.I)
# Claude Code's folder names for projects encode the path: -Users-<name>-Desktop-...
ENCODED_HOME = re.compile(r"-(Users|home)-[A-Za-z][\w.]*-", re.I)
SECRET = re.compile(r"(sk-ant-[\w-]{10,}|sk-[A-Za-z0-9]{32,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_\w{20,}"
                    r"|AKIA[0-9A-Z]{16}|xox[abpr]-[\w-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)")
SESSION_ID = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b")
TEXT_EXT = (".py", ".md", ".swift", ".sh", ".plist", ".yml", ".yaml", ".json", ".html", ".svg", ".txt", ".cfg")


def published_files():
    try:
        out = subprocess.run(["git", "ls-files"], cwd=REPO, capture_output=True, text=True, check=True).stdout
        files = [f for f in out.splitlines() if f]
        if files:
            return files
    except (OSError, subprocess.CalledProcessError):
        pass
    skip = {".git", "build", "__pycache__"}
    found = []
    for root, dirs, names in os.walk(REPO):
        dirs[:] = [d for d in dirs if d not in skip]
        found += [os.path.relpath(os.path.join(root, n), REPO) for n in names]
    return found


class NoPrivateData(unittest.TestCase):
    def test_text_files(self):
        problems = []
        for rel in published_files():
            if not rel.endswith(TEXT_EXT) or rel == os.path.join("tests", "test_no_private_data.py"):
                continue
            with open(os.path.join(REPO, rel), encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            for email in EMAIL.findall(text):
                if not ALLOWED_EMAIL.search(email):
                    problems.append("%s: email %s" % (rel, email))
            problems += ["%s: home path %s" % (rel, m.group(0)) for m in HOME_PATH.finditer(text)]
            problems += ["%s: encoded home path %s" % (rel, m.group(0)) for m in ENCODED_HOME.finditer(text)]
            problems += ["%s: secret-like %s…" % (rel, m.group(0)[:12]) for m in SECRET.finditer(text)]
            problems += ["%s: session id %s" % (rel, m) for m in SESSION_ID.findall(text)]
        self.assertEqual(problems, [])

    def test_images_carry_no_text(self):
        """PNG text chunks can hold paths, user names or tool versions."""
        problems = []
        for rel in published_files():
            if not rel.endswith(".png"):
                continue
            with open(os.path.join(REPO, rel), "rb") as fh:
                data = fh.read()
            pos = 8
            while pos + 8 <= len(data):
                size, kind = struct.unpack(">I", data[pos:pos + 4])[0], data[pos + 4:pos + 8]
                if kind in (b"tEXt", b"iTXt", b"zTXt"):
                    problems.append("%s: %s chunk" % (rel, kind.decode()))
                pos += 12 + size
        self.assertEqual(problems, [])

    def test_no_data_files(self):
        """No index, transcript or report ever ships with the code."""
        bad = [f for f in published_files()
               if f.endswith((".jsonl", ".csv")) or os.path.basename(f) in ("index.json", "categories.json",
                                                                          "predictor.json")]
        self.assertEqual(bad, [])


if __name__ == "__main__":
    unittest.main()
