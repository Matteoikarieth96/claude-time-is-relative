"""Synthetic Claude Code transcripts for the tests: no real session is ever used."""
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(REPO, "task_eta.py")
INSTALL = os.path.join(REPO, "install.py")
T0 = 1_790_000_000.0  # a fixed start time


def iso(ts):
    return datetime.fromtimestamp(ts, timezone.utc).isoformat().replace("+00:00", "Z")


class Transcript:
    """Builds one session transcript, record by record, on a fake clock."""

    def __init__(self, session="s1", cwd="/work/acme", model="claude-opus-5-5", effort="high"):
        self.session, self.cwd, self.model, self.effort = session, cwd, model, effort
        self.records = []
        self.n = 0

    def _id(self, prefix):
        self.n += 1
        return "%s%d" % (prefix, self.n)

    def prompt(self, ts, text, origin="human", entrypoint="cli"):
        rec = {"type": "user", "timestamp": iso(ts), "sessionId": self.session, "cwd": self.cwd,
               "entrypoint": entrypoint, "message": {"role": "user", "content": text}}
        if origin:
            rec["origin"] = {"kind": origin}
        self.records.append(rec)

    def say(self, ts, text, end=False):
        self.records.append({"type": "assistant", "timestamp": iso(ts), "effort": self.effort,
                             "message": {"id": self._id("msg"), "model": self.model,
                                         "content": [{"type": "text", "text": text}],
                                         "stop_reason": "end_turn" if end else None}})

    def tool(self, ts, name, tool_input, result_ts, result="ok"):
        tid = self._id("toolu_")
        self.records.append({"type": "assistant", "timestamp": iso(ts), "effort": self.effort,
                             "message": {"id": self._id("msg"), "model": self.model, "stop_reason": "tool_use",
                                         "content": [{"type": "tool_use", "id": tid, "name": name,
                                                      "input": tool_input}]}})
        self.records.append({"type": "user", "timestamp": iso(result_ts),
                             "message": {"role": "user", "content": [
                                 {"type": "tool_result", "tool_use_id": tid, "content": result}]}})
        return tid

    def stop(self, ts):
        self.records.append({"type": "system", "subtype": "stop_hook_summary", "timestamp": iso(ts)})

    def task(self, start, prompt, steps=5, step_s=10.0, estimate=None, edit="app.py"):
        """A whole task: prompt, optional ⏱ line, `steps` tool calls, a final answer, the Stop."""
        self.prompt(start, prompt)
        ts = start + 2
        if estimate:
            self.say(ts, estimate)
        for _ in range(steps):
            self.tool(ts + 1, "Edit", {"file_path": "/work/acme/" + edit}, ts + step_s)
            ts += step_s
        self.say(ts + 2, "Done.", end=True)
        self.stop(ts + 3)
        return ts + 3

    def write(self, projects_dir, project="-work-acme"):
        folder = os.path.join(projects_dir, project)
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, self.session + ".jsonl")
        with open(path, "w", encoding="utf-8") as fh:
            for rec in self.records:
                # Compact, as Claude Code writes its transcripts.
                fh.write(json.dumps(rec, ensure_ascii=False, separators=(",", ":")) + "\n")
        return path


def clean_env(home):
    """An environment that points everything at a temporary home, never at the real one."""
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("CLAUDE", "TASK_ETA", "ANTHROPIC"))}
    env["HOME"] = home
    env["CLAUDE_CONFIG_DIR"] = os.path.join(home, ".claude")
    # macOS's system Python caches bytecode under $HOME: the Stop hook's background calibration
    # would keep writing there while the test deletes the folder.
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


def remove_tmp(tmp):
    """Delete a TemporaryDirectory. A Stop hook leaves its calibration running in the background
    for a moment, so a folder that is still being written is tried again for up to 10 s."""
    for _ in range(40):
        try:
            shutil.rmtree(tmp.name)
            break
        except FileNotFoundError:
            break
        except OSError:
            time.sleep(0.25)
    tmp.cleanup()


def run(args, home, stdin=None, extra_env=None, script=SCRIPT):
    env = clean_env(home)
    env.update(extra_env or {})
    return subprocess.run([sys.executable, script] + list(args), input=stdin, env=env,
                          capture_output=True, text=True, timeout=60)
