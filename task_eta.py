#!/usr/bin/env python3
"""task-eta: measure how long Claude Code tasks really take, and estimate new ones.

Claude Code already writes every session to ~/.claude/projects/*/*.jsonl.
This script turns each human prompt in those transcripts into a "task"
with its real duration and keeps them in ~/.claude/task-eta/index.json.
Nothing else is recorded: the transcripts are the only source, and nothing
leaves this machine (no network code, standard library only).

Commands:
  update [--force] [--file PATH]   parse new or changed transcripts into the index
  estimate TEXT          past durations of tasks similar to TEXT
  report                 summary of all tasks and of past estimates
  calibrate              re-measure the correction factor of the suggested estimate
  elapsed                real time of the task in progress, for the last line of the reply
  eta                    updated remaining time of the task in progress, for intermediate messages
  status [--json]        tasks in progress and the last finished ones (from live/, for the widget)
  hook-prompt            UserPromptSubmit hook: adds the history block to the prompt
  hook-stop              Stop hook: updates the index, shows estimate vs real time
  hook-input             PreToolUse/PermissionRequest/Notification hook: Claude waits for the user (widget)
  export-unlabeled FILE  work tasks with no category label yet, as JSONL (optional labelling)
  import-labels FILE...  merge {task key: category} JSON files into categories.json

Written for Python 3.9+ with the standard library only, so the hooks run
with whatever python3 the machine has.
"""
import glob
import hashlib
import json
import math
import os
import re
import shlex
import sys
import time
import unicodedata
from collections import Counter
from datetime import datetime

HOME = os.path.expanduser("~")
# Claude Code's own folder: ~/.claude, unless CLAUDE_CONFIG_DIR moves it.
CLAUDE_DIR = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
PROJECTS = os.path.join(CLAUDE_DIR, "projects")
DATA_DIR = os.environ.get("TASK_ETA_DIR") or os.path.join(CLAUDE_DIR, "task-eta")
INDEX = os.path.join(DATA_DIR, "index.json")
LABELS = os.path.join(DATA_DIR, "categories.json")  # optional labels of past tasks (import-labels)
PREDICTOR = os.path.join(DATA_DIR, "predictor.json")  # correction factor of the suggested estimate
# One small JSON per task, for the desktop widget: <session>.json is the session's current
# task, <session>-<start>.json an earlier finished one. Written by the two hooks only.
LIVE_DIR = os.environ.get("TASK_ETA_LIVE_DIR") or os.path.join(DATA_DIR, "live")
LIVE_KEEP_DONE = 20        # finished tasks kept in live/
LIVE_MAX_AGE_S = 24 * 3600  # older live files are deleted
LIVE_OFF = os.path.join(DATA_DIR, "live.off")  # if this file exists, the hooks write no live files
# {"since": unix time}: written by install.py when the user chose not to read older sessions.
CONFIG = os.path.join(DATA_DIR, "config.json")
# The Claude desktop app's own file for each session (macOS): <account>/<org>/<host session id>.json,
# with the model and effort picked in the app right now. Read only, and only if it exists.
APP_SESSIONS = os.path.join(HOME, "Library", "Application Support", "Claude", "claude-code-sessions")

IDLE_CAP_S = 60 * 60     # a pause between turns longer than this is idle time, not work
SILENCE_CAP_S = 15 * 60  # silence this long inside a turn (no subagent running) = waiting on the user
CALL_CAP_S = 10 * 60     # one model call longer than this was not all model time
STALE_TURN_S = 10 * 60   # a prompt this long after the last activity starts a new task
SNIPPET = 300            # characters of each prompt kept in the index
MIN_SIM = 0.15           # cosine similarity below this is not "similar"
STRONG_SIM = 0.5         # from this similarity on, the similar tasks alone make the estimate
# Words that usually mean parallel subagents ("*" = any word starting so).
AGENT_WORDS = ("dd diligence deep agent* subagent* parallel* workflow thorough* exhaustive* "
               "approfondit* esaustiv*").split()

# The first ⏱ line of a reply: "⏱ Estimated time with opus-5-5 xhigh: ~10 min (likely 4 to 24 min)".
# Also reads lines written by older versions, in Italian: "⏱ Tempo richiesto con ...: ~10 min",
# "⏱ Stima: ~8-12 min", "⏱ Stima: ~1,5 h".
# The pattern is applied to one line cut to EST_LINE characters, and has no nested or adjacent
# open-ended repeats, so a hostile line cannot make it slow.
EST_RE = re.compile(
    r"⏱️?[^\n:]{0,200}:[ \t]*(?:\*\*[ \t]*)?(?:~[ \t]*)?"
    r"(\d{1,9}(?:[.,]\d{1,3})?)(?:[ \t]*[-–][ \t]*~?(\d{1,9}(?:[.,]\d{1,3})?))?[ \t]*"
    r"(hours?|h|ore|ora|minutes?|min|m|seconds?|sec|s)?\b",
)
EST_LINE = 300
EST_MAX_MIN = 7 * 24 * 60  # an "estimate" longer than a week is not one
# ⏱ lines that report time, not estimate it (this tool's own closing lines, in both languages).
NOT_ESTIMATE = ("Actual time", "Elapsed", "Tempo reale", "Trascorso")
CAT_RE = re.compile(r"\[([a-z]+)\]")

CATEGORIES = [
    ("coding", "code: apps, sites, bugs, deploys, repos, PRs, scripts"),
    ("research", "research: due diligence, deep research, studying a project, market or job"),
    ("documents", "documents to read: decks, reports, letters, applications, guides"),
    ("social", "posts and threads for X or LinkedIn, social infographics"),
    ("design", "visual design: labels, logos, illustrations, images"),
    ("video", "videos: explainers, animation, voiceover, rendering"),
    ("hardware", "3D printing, electronics, wiring, devices"),
    ("setup", "configuring Claude and tools: skills, hooks, memory, settings, files"),
    ("other", "everything else: quick questions, calculations, admin"),
]
CAT_CODES = [code for code, _ in CATEGORIES]
# Category names written by older versions (Italian), and "followup" for a request that only
# continues the one before it (e.g. "go on").
LEGACY_CATS = {"ricerca": "research", "documenti": "documents", "grafica": "design",
               "altro": "other", "seguito": "followup"}
# Fallback rules for tasks nobody labelled ("*" = any word starting so). English, plus the
# Italian words the author types; add the words of your own language here.
CAT_WORDS = {
    "coding": "code bug fix deploy repo github pr commit branch api frontend backend staging "
              "script npm python typescript javascript endpoint database server build test error "
              "crash refactor merge codice errore".split(),
    "research": "dd diligence research analy* study compare competitor* market job* "
                "ricerc* analizz* analisi studia valut* confront* mercato lavoro".split(),
    "documents": "deck slide* presentation* document doc docs report pdf letter email mail contract "
                 "guide cv resume application one-pager excel xlsx docx summary "
                 "presentazion* documento lettera contratto guida candidatura riassunto".split(),
    "social": "post thread tweet linkedin instagram caption infographic social infografica".split(),
    "design": "label logo image* illustration* graphic* design banner colour* color* figma "
              "draw* icon* etichett* immagin* illustrazion* grafica disegn* icona".split(),
    "video": "video whiteboard voiceover voice trailer mp4 animation* voce montaggio animazion*".split(),
    "hardware": "print* printer gcode stl 3d filament nozzle arduino wiring usb sensor esp32 "
                "raspberry stampa stampare stampante cablaggio".split(),
    "setup": "skill skills hook hooks memory settings mcp plugin connector* config* permission* "
             "folder* install* memoria connettor* permess* cartell*".split(),
}
CODE_EXTS = set("py ts tsx js jsx mjs cjs sol rs go css scss vue svelte sh sql swift".split())
# Prompts that are not a new request: an agent finishing, a message from another session.
SKIP_PROMPTS = ("<task-notification", "[SYSTEM NOTIFICATION", "<side-sessions-event",
                "<ci-monitor-event", "<agent-message")
# Wake-ups that are not work of this session: the pause before them was idle time, not
# work. A side session's time is measured in its own transcript, never in the session that
# started it. Any other wake-up (a background agent or command finishing, a subagent's
# <agent-message>, even if it reads "Another Claude session sent a message") is this
# session's own work, so the pause before it counts. An empty one (reminders only) is not.
FOREIGN_WAKES = ("<side-sessions-event", "<ci-monitor-event", "<command-name",
                 "<artifact-content-authored-by-others", "The app was quit")
# First message of a session started by another one (start_session): background, then the task.
SPAWN_PREFIX = "Background (from the session that started this one):"
SPAWN_TASK = "\nTask:\n"
INTERRUPT = "[Request interrupted by user"
END_REASONS = ("end_turn", "stop_sequence")
WAKE_TOOLS = {"Agent", "Task", "Workflow"}
EFFORTS = {"low": 0, "medium": 1, "high": 2, "xhigh": 3, "max": 4}
# Blocks the app wraps around a prompt (reminders, attached context): dropped with their content.
DROP_OPEN = re.compile(r"<(system-reminder|artifact-view-context[\w-]*|command-message|local-command-stdout)\b[^>]*>")
MAX_TEXT = 200_000  # characters of one message looked at
ANY_TAG = re.compile(r"</?[a-zA-Z][\w-]*(?:\s[^<>]*)?>")

STOPWORDS = set(
    """
    che per con non una uno del della dello dei delle degli nel nella nello nei nelle sul sulla
    sui sulle alla alle allo agli dal dalla dai dagli come anche sono questo questa questi queste
    quello quella quelli più piu poi fai fare puoi può puo gli tra fra hai abbiamo hanno essere
    stato stata era cosa tutto tutti tutte ogni dove quando perché perche quindi allora ora già
    gia solo ancora bene così cosi molto voglio vorrei fammi dimmi secondo mio mia miei mie tuo
    tua suo sua nostro anzi oppure dopo prima sempre the and for with that this from you your
    are was were have has can will would should could into about what which when where there
    their they them then than also just like make https http www com html
    di da in su il lo la le gli mi ti ci vi si se ma ho ha fa ok no un uno ne è e a o
    to of on at is it be do we me my or an as by up so if
    """.split()
)
WORD = re.compile(r"[a-zà-ÿ0-9]{2,}")


# ---------------------------------------------------------------- parsing

TS_MIN, TS_MAX = 946684800, 4102444800  # 2000 to 2100: anything else is not a real timestamp


def parse_ts(value):
    if not value or not isinstance(value, str):
        return None
    try:
        ts = datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError, OverflowError, OSError):
        return None
    return ts if TS_MIN <= ts <= TS_MAX else None


def iso(ts):
    return datetime.fromtimestamp(ts).astimezone().isoformat(timespec="seconds")


def load_record(line):
    """One transcript line as a dict, or None (bad JSON, nesting too deep, not an object)."""
    try:
        rec = json.loads(line)
    except (ValueError, RecursionError):
        return None
    if not isinstance(rec, dict):
        return None
    if not isinstance(rec.get("message", {}), dict):
        rec["message"] = {}
    return rec


def regular_file(path):
    """True for a plain file: a FIFO, a device or a folder would hang or break a read."""
    try:
        return isinstance(path, str) and os.path.isfile(path)
    except (OSError, ValueError):
        return False


def drop_tags(text):
    """The text without the wrapped blocks (DROP_OPEN ... </same tag>). Linear: a tag whose closing
    is not found once is never searched for again, so unclosed tags cannot make it slow."""
    out, pos, unclosed = [], 0, set()
    while True:
        m = DROP_OPEN.search(text, pos)
        while m and m.group(1) in unclosed:
            m = DROP_OPEN.search(text, m.end())
        if not m:
            out.append(text[pos:])
            return "".join(out)
        close = text.find("</%s>" % m.group(1), m.end())
        if close < 0:
            unclosed.add(m.group(1))
            out.append(text[pos:m.end()])
            pos = m.end()
            continue
        out.append(text[pos:m.start()])
        out.append(" ")
        pos = close + len(m.group(1)) + 3


def clean_prompt(text):
    # A lone surrogate (half an emoji) would break every later UTF-8 write of the index.
    text = str(text)[:MAX_TEXT].encode("utf-8", "replace").decode("utf-8")
    text = ANY_TAG.sub(" ", drop_tags(text))
    return re.sub(r"\s+", " ", text).strip()


def record_text(rec):
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, list):
        return " ".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return content if isinstance(content, str) else ""


def wake_body(text):
    """A wake-up message without the reminders the app puts in front of it."""
    return drop_tags(str(text or "")[:MAX_TEXT]).lstrip()


def own_wake(text):
    """True if this wake-up reports work of this session (see FOREIGN_WAKES)."""
    body = wake_body(text)
    return bool(body) and not body.startswith(FOREIGN_WAKES)


def spawn_prompt(text):
    """The task given to a session started by another session, or None."""
    text = (text or "").lstrip()
    if not text.startswith(SPAWN_PREFIX):
        return None
    task = text.split(SPAWN_TASK, 1)
    return clean_prompt(task[1] if len(task) == 2 else text[len(SPAWN_PREFIX):]) or None


def human_prompt(rec):
    """The prompt text if this record is a message the user typed, else None."""
    if rec.get("type") != "user" or rec.get("isMeta"):
        return None
    origin = (rec.get("origin") or {}).get("kind")
    # Headless runs (claude -p) record the prompt with no origin at all.
    headless = origin is None and rec.get("entrypoint") == "sdk-cli"
    if origin != "human" and not headless:
        return None
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        blocks = [b for b in content if isinstance(b, dict)]
        if any(b.get("type") == "tool_result" for b in blocks):
            return None
        text = " ".join(b.get("text", "") for b in blocks if b.get("type") == "text")
        if not text.strip() and any(b.get("type") == "image" for b in blocks):
            text = "[image]"
    else:
        return None
    if text.startswith(INTERRUPT):
        return None
    return clean_prompt(text) or "[empty]"


def estimate_line(text):
    """The first ⏱ line that gives an estimate (not a closing "Actual time" line), cut short."""
    for line in (text or "").splitlines():
        if "⏱" in line and not any(word in line for word in NOT_ESTIMATE):
            return line[:EST_LINE]
    return ""


def parse_estimate(text):
    """(minutes, category) from the first ⏱ estimate line, or (None, None)."""
    line = estimate_line(text)
    m = EST_RE.search(line) if line else None
    if not m:
        return None, None
    low = float(m.group(1).replace(",", "."))
    high = float(m.group(2).replace(",", ".")) if m.group(2) else low
    minutes = (low + high) / 2
    unit = (m.group(3) or "min").lower()
    if unit in ("h", "hour", "hours", "ore", "ora"):
        minutes *= 60
    elif unit in ("s", "sec", "second", "seconds"):
        minutes /= 60
    if not 0 < minutes <= EST_MAX_MIN:
        return None, None
    cat = CAT_RE.search(line[:m.end()])
    cat = LEGACY_CATS.get(cat.group(1), cat.group(1)) if cat else None
    return round(minutes, 1), (cat if cat in CAT_CODES else None)


def new_task(rec, ts, text):
    return {
        "start": ts,
        "prompt": text[:SNIPPET],
        "cwd": os.path.basename(rec.get("cwd") or ""),
        "session": rec.get("sessionId") or "",
        "headless": rec.get("entrypoint") == "sdk-cli",  # a `claude -p` run (tests, scripts)
        "running": False,
        "trigger": ts,        # what woke Claude up for the next segment
        "trigger_own": True,  # woken by this session's own work (see FOREIGN_WAKES)
        "seg_start": None,
        "last": ts,
        "last_stop": None,
        "ended_at": None,     # last assistant message that ended its turn
        "pending_agents": set(),
        "agent_ids": [],      # tool_use ids of the Agent/Workflow calls, to find their transcripts
        "call_marks": [],
        "active": 0.0,
        "wait": 0.0,
        "idle": 0.0,
        "segments": 0,
        "tools": 0,
        "agents": 0,
        "asks": {},
        "estimate_min": None,
        "category": None,     # declared by Claude in its estimate line
        "est_range": None,    # "likely X to Y" of the estimate line, in seconds
        "interrupted": False,
        "models": Counter(),
        "efforts": Counter(),
        "tool_names": Counter(),
        "edit_exts": Counter(),
        "call_from": ts,      # when the input of the next model call was ready
        "msg_id": None,
        "msg_start": ts,
        "msg_counted": 0.0,
        "calls_by": {},       # "model|effort" -> [calls, seconds of model time]
    }


def stop_segment(cur, ts):
    if cur["running"]:
        cur["active"] += max(0.0, ts - cur["seg_start"])
        cur["running"] = False
    cur["last_stop"] = ts
    cur["last"] = max(cur["last"], ts)
    cur["ended_at"] = None


def top(counter):
    return counter.most_common(1)[0][0] if counter else None


def short_model(model):
    return model[len("claude-"):] if model and model.startswith("claude-") else model


def finish(cur, path):
    if cur["running"] and cur["ended_at"] is not None:
        stop_segment(cur, cur["ended_at"])
    still_running = cur["running"]
    if still_running:
        cur["active"] += max(0.0, cur["last"] - cur["seg_start"])
    wall = cur["last"] - cur["start"] - cur["wait"] - cur["idle"]
    active = cur["active"] - cur["wait"]
    # Woken up again and again by background watchers (no subagents), working a few
    # seconds each time: the wall clock measures the thing being watched, not the work.
    monitor = cur["segments"] >= 4 and active < 0.25 * wall and cur["agents"] == 0
    key_src = "%.3f|%s" % (cur["start"], cur["prompt"][:200])
    return {
        "key": hashlib.sha1(key_src.encode("utf-8", "replace")).hexdigest()[:16],
        "start": iso(cur["start"]),
        "start_ts": round(cur["start"], 3),
        "dur_s": round(max(0.0, wall), 1),
        "active_s": round(max(0.0, active), 1),
        "wait_s": round(cur["wait"], 1),
        "segments": cur["segments"],
        "tools": cur["tools"],
        "agents": cur["agents"],
        "agent_ids": cur["agent_ids"],
        "call_marks": cur["call_marks"],
        "end_ts": round(cur["last"], 3),
        "estimate_min": cur["estimate_min"],
        "category": cur["category"],
        "est_range": cur["est_range"],
        "interrupted": cur["interrupted"],
        "monitor": monitor,
        "open": still_running,
        "model": short_model(top(cur["models"])),
        "effort": top(cur["efforts"]),
        "calls_by": {k: [v[0], round(v[1], 1)] for k, v in cur["calls_by"].items()},
        "model_s": round(sum(v[1] for v in cur["calls_by"].values()), 1),
        "tool_names": dict(cur["tool_names"].most_common(6)),
        "edit_exts": dict(cur["edit_exts"].most_common(4)),
        "cwd": cur["cwd"],
        "session": cur["session"],
        "headless": cur["headless"],
        "file": path,
        "prompt": cur["prompt"],
    }


def parse_transcript(path):
    """Split one transcript into tasks: a human prompt plus all the work it caused."""
    tasks, cur = [], None

    def close():
        if cur is not None and cur["segments"] > 0:
            tasks.append(finish(cur, path))

    if not regular_file(path):
        return []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            rec = load_record(line)
            if rec is None or rec.get("isSidechain"):
                continue
            ts = parse_ts(rec.get("timestamp"))
            if ts is None:
                continue
            kind = rec.get("type")
            if kind not in ("user", "assistant", "system"):
                continue

            # Silence inside a turn with no subagent running and no question pending
            # (those are counted apart): a permission prompt or a stuck turn, not work.
            if cur is not None and cur["running"] and not cur["pending_agents"] and not cur["asks"]:
                gap = ts - cur["last"]
                if gap > SILENCE_CAP_S:
                    cur["idle"] += gap

            text = human_prompt(rec)
            if text is None and cur is None and kind == "user" and not rec.get("isMeta"):
                # A session started by another session: the brief it got is its first prompt.
                text = spawn_prompt(record_text(rec))
            if text is not None:
                if cur is not None and cur["running"] and cur["ended_at"] is not None:
                    stop_segment(cur, cur["ended_at"])
                # Typed while Claude was still working on the previous one: same task.
                if cur is not None and cur["running"] and ts - cur["last"] < STALE_TURN_S:
                    cur["last"] = max(cur["last"], ts)
                    continue
                close()
                cur = new_task(rec, ts, text)
                continue
            if cur is None:
                continue

            if kind == "assistant":
                msg = rec.get("message") or {}
                if not cur["running"]:
                    seg_start = cur["trigger"] if cur["trigger"] is not None else ts
                    pause = seg_start - cur["last_stop"] if cur["last_stop"] is not None else 0.0
                    if pause > IDLE_CAP_S or (pause > 0 and not cur["trigger_own"]):
                        cur["idle"] += pause
                    cur["seg_start"] = seg_start
                    cur["running"] = True
                    cur["segments"] += 1
                    cur["trigger"] = None
                cur["last"] = max(cur["last"], ts)
                model = msg.get("model")
                effort = rec.get("perTurnEffort") or rec.get("effort")
                if model and not model.startswith("<"):
                    cur["models"][model] += 1
                    if effort:
                        cur["efforts"][effort] += 1
                    # One API call = one message id, written as one record per block.
                    # Its time runs from when its input was ready to its last block.
                    combo = "%s|%s" % (short_model(model), effort or "?")
                    stats = cur["calls_by"].setdefault(combo, [0, 0.0])
                    if msg.get("id") != cur["msg_id"]:
                        cur["msg_id"] = msg.get("id")
                        stats[0] += 1
                        cur["msg_start"] = cur["call_from"]
                        if len(cur["call_marks"]) < 40:  # seconds from the prompt to each model call
                            cur["call_marks"].append(round(cur["call_from"] - cur["start"] - cur["wait"] - cur["idle"], 1))
                        cur["msg_counted"] = 0.0
                    spent = min(CALL_CAP_S, max(0.0, ts - cur["msg_start"]))
                    stats[1] += spent - cur["msg_counted"]
                    cur["msg_counted"] = spent
                cur["call_from"] = ts
                cur["ended_at"] = ts if msg.get("stop_reason") in END_REASONS else None
                for block in msg.get("content") or []:
                    if not isinstance(block, dict):
                        continue
                    btype = block.get("type")
                    if btype == "tool_use":
                        cur["tools"] += 1
                        name = block.get("name") or ""
                        cur["tool_names"][name.split("__")[-1] if name.startswith("mcp__") else name] += 1
                        target = str((block.get("input") or {}).get("file_path") or "")
                        if name in ("Edit", "Write", "NotebookEdit") and "." in os.path.basename(target):
                            cur["edit_exts"][target.rsplit(".", 1)[-1].lower()[:8]] += 1
                        if name in WAKE_TOOLS:
                            cur["agents"] += 1
                            cur["pending_agents"].add(block.get("id"))
                            cur["agent_ids"].append(block.get("id"))
                        if name == "AskUserQuestion":
                            cur["asks"][block.get("id")] = ts
                    elif btype == "text" and cur["estimate_min"] is None and cur["tools"] == 0:
                        # Only the opening of the reply, before any tool: an example
                        # quoted later in the text is not an estimate.
                        cur["estimate_min"], cur["category"] = parse_estimate(block.get("text") or "")
                        cur["est_range"] = parse_range(block.get("text") or "") if cur["estimate_min"] else None

            elif kind == "user":
                cur["call_from"] = ts
                content = (rec.get("message") or {}).get("content")
                blocks = content if isinstance(content, list) else [{"type": "text", "text": content or ""}]
                is_result = False
                for block in blocks:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "tool_result":
                        is_result = True
                        cur["pending_agents"].discard(block.get("tool_use_id"))
                        asked = cur["asks"].pop(block.get("tool_use_id"), None)
                        if asked is not None:
                            cur["wait"] += max(0.0, ts - asked)
                    elif str(block.get("text", "")).startswith(INTERRUPT):
                        cur["interrupted"] = True
                        stop_segment(cur, ts)
                if not is_result:
                    # Something woke Claude up: an agent or command finished, a message
                    # from another session. The turn before it, if any, ended there.
                    if cur["running"] and cur["ended_at"] is not None:
                        stop_segment(cur, cur["ended_at"])
                    if not cur["running"]:
                        if cur["trigger"] is None:
                            cur["trigger"], cur["trigger_own"] = ts, False
                        if own_wake(record_text(rec)):
                            cur["trigger_own"] = True
                cur["last"] = max(cur["last"], ts) if cur["running"] else cur["last"]

            elif kind == "system" and rec.get("subtype") == "stop_hook_summary":
                stop_segment(cur, ts)
    close()
    for prev, task in zip([None] + tasks[:-1], tasks):
        task["prev_key"] = prev["key"] if prev else None
    attach_subagents(path, tasks)
    return tasks


def parse_subagent(path):
    """One subagent transcript: its span, tool calls and model time per model/effort."""
    first = last = None
    calls_by, tools = {}, 0
    msg_id, call_from, msg_start, counted = None, None, None, 0.0
    task_text = None
    if not regular_file(path):
        return None
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return None
    with fh:
        for line in fh:
            rec = load_record(line)
            ts = parse_ts(rec.get("timestamp")) if rec else None
            if ts is None:
                continue
            first = ts if first is None else min(first, ts)
            last = ts if last is None else max(last, ts)
            if rec.get("type") == "user":
                call_from = ts
                if task_text is None and not rec.get("isMeta"):
                    c = (rec.get("message") or {}).get("content")
                    task_text = c if isinstance(c, str) else " ".join(
                        b.get("text", "") for b in c or [] if isinstance(b, dict) and b.get("type") == "text")
            elif rec.get("type") == "assistant":
                msg = rec.get("message") or {}
                model = msg.get("model")
                if model and not model.startswith("<"):
                    effort = rec.get("perTurnEffort") or rec.get("effort") or "?"
                    stats = calls_by.setdefault("%s|%s" % (short_model(model), effort), [0, 0.0])
                    if msg.get("id") != msg_id:
                        msg_id, msg_start, counted = msg.get("id"), call_from or ts, 0.0
                        stats[0] += 1
                    spent = min(CALL_CAP_S, max(0.0, ts - msg_start))
                    stats[1] += spent - counted
                    counted = spent
                tools += sum(1 for b in msg.get("content") or [] if isinstance(b, dict) and b.get("type") == "tool_use")
                call_from = ts
    if first is None:
        return None
    return {"start": first, "end": last, "tools": tools, "calls_by": calls_by,
            "prompt": clean_prompt(task_text or "")[:400]}


def attach_subagents(path, tasks):
    """Link the subagents of a session (<session>/subagents/agent-*.jsonl) to the task that
    started them: by the Agent call id in their .meta.json, else by when they ran.
    Adds task["sub"]: how many, busy_s (time at least one ran), work_s (their summed
    spans), model_s and calls_by (their model time per model/effort)."""
    folder = os.path.join(path[:-len(".jsonl")], "subagents")
    if not tasks or not os.path.isdir(folder):
        return
    by_call = {}
    for t in tasks:
        for tool_id in t.get("agent_ids") or []:
            by_call[tool_id] = t
    groups = {}
    for name in os.listdir(folder):
        if not name.endswith(".jsonl"):
            continue
        sub = parse_subagent(os.path.join(folder, name))
        if not sub:
            continue
        owner = None
        meta = os.path.join(folder, name[:-len(".jsonl")] + ".meta.json")
        try:
            if regular_file(meta):
                with open(meta, encoding="utf-8") as fh:
                    owner = by_call.get(json.load(fh).get("toolUseId"))
        except (OSError, ValueError, RecursionError, AttributeError, TypeError):
            pass
        if owner is None:
            owner = next((t for t in tasks if t["start_ts"] - 5 <= sub["start"] <= t.get("end_ts", 0) + 5), None)
        if owner is not None:
            groups.setdefault(owner["key"], []).append(sub)
    for t in tasks:
        subs = groups.get(t["key"])
        if not subs:
            continue
        # Only the part inside the task counts: an agent can outlive the task that started it.
        lo, hi = t["start_ts"], t.get("end_ts") or t["start_ts"]
        spans = sorted((max(lo, s["start"]), min(hi, s["end"])) for s in subs)
        spans = [(a, b) for a, b in spans if b > a] or [(lo, lo)]
        busy, cur_start, cur_end = 0.0, spans[0][0], spans[0][1]
        for a, b in spans[1:]:
            if a > cur_end:
                busy += cur_end - cur_start
                cur_start, cur_end = a, b
            else:
                cur_end = max(cur_end, b)
        busy += cur_end - cur_start
        calls_by = {}
        for s in subs:
            for combo, (n, secs) in s["calls_by"].items():
                acc = calls_by.setdefault(combo, [0, 0.0])
                acc[0] += n
                acc[1] += secs
        t["sub"] = {"n": len(subs), "busy_s": round(busy, 1),
                    "work_s": round(sum(s["end"] - s["start"] for s in subs), 1),
                    "tools": sum(s["tools"] for s in subs),
                    "model_s": round(sum(v[1] for v in calls_by.values()), 1),
                    "calls_by": {k: [v[0], round(v[1], 1)] for k, v in calls_by.items()},
                    "agents": [{"prompt": s["prompt"], "dur_s": round(s["end"] - s["start"], 1),
                                "model": short_model(top(Counter({c.split("|")[0]: v[0] for c, v in s["calls_by"].items()}))) if s["calls_by"] else None}
                               for s in subs]}


# ---------------------------------------------------------------- index

def load_index():
    """The index; an index this version cannot read is moved aside (never overwritten), because it
    may hold tasks whose transcripts Claude Code has deleted since."""
    try:
        with open(INDEX, encoding="utf-8") as fh:
            idx = json.load(fh)
        if isinstance(idx, dict) and idx.get("version") == 1 and isinstance(idx.get("tasks"), dict) \
                and isinstance(idx.get("files"), dict):
            return idx
    except FileNotFoundError:
        return {"version": 1, "files": {}, "tasks": {}}
    except (OSError, ValueError, RecursionError):
        pass
    try:
        os.replace(INDEX, "%s.unreadable-%d" % (INDEX, time.time()))
    except OSError:
        pass
    return {"version": 1, "files": {}, "tasks": {}}


def write_json(path, data, **kw):
    """Atomic: a temporary file next to it, then a rename."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = "%s.%d.tmp" % (path, os.getpid())
    try:
        text = json.dumps(data, ensure_ascii=False, **kw)
        text.encode("utf-8")
    except UnicodeEncodeError:
        text = json.dumps(data, ensure_ascii=True, **kw)  # a lone surrogate somewhere: escape it
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


def save_index(idx):
    write_json(INDEX, idx, separators=(",", ":"))


def history_since():
    """Tasks that started before this are left out: the user chose not to read older sessions."""
    try:
        with open(CONFIG, encoding="utf-8") as fh:
            return float(json.load(fh).get("since") or 0)
    except (OSError, ValueError, TypeError, AttributeError):
        return 0.0


def update(paths=None, force=False):
    """Parse transcripts that changed since the last run. Tasks are never deleted,
    so the history survives when Claude Code cleans up old transcripts."""
    idx = load_index()
    since = history_since()
    if paths is None:
        paths = glob.glob(os.path.join(glob.escape(PROJECTS), "*", "*.jsonl"))
        check_sig = not force
    else:
        check_sig = False
    changed = 0
    for path in paths:
        if not regular_file(path):
            continue
        try:
            st = os.stat(path)
        except OSError:
            continue
        sig = [round(st.st_mtime, 3), st.st_size]
        if check_sig and idx["files"].get(path) == sig:
            continue
        for task in parse_transcript(path):
            if task["start_ts"] >= since:
                idx["tasks"][task["key"]] = task
        idx["files"][path] = sig
        changed += 1
    if changed:
        save_index(idx)
    return idx, changed


def is_work(task):
    return task["tools"] > 0 and not task["interrupted"] and not task.get("monitor")


def finished_tasks(idx):
    return [t for t in idx["tasks"].values()
            if not t.get("open") and 0 < t["dur_s"] < 12 * 3600]


# ---------------------------------------------------------------- stats

def pct(values, q):
    if not values:
        return None
    vals = sorted(values)
    pos = (len(vals) - 1) * q
    lo, hi = int(math.floor(pos)), int(math.ceil(pos))
    return vals[lo] + (vals[hi] - vals[lo]) * (pos - lo)


def fmt(seconds):
    if seconds is None:
        return "n/d"
    if seconds < 90:
        return "%d s" % round(seconds)
    if seconds < 90 * 60:
        return "%d min" % round(seconds / 60)
    return ("%.1f h" % (seconds / 3600)).replace(".0 h", " h")


def tokens(text):
    return {w for w in WORD.findall(text.lower()) if w not in STOPWORDS}


def similar(text, tasks, k=5):
    query = tokens(text)
    if not query:
        return []
    docs = [(t, tokens(t["prompt"])) for t in tasks]
    df = Counter()
    for _, words in docs:
        df.update(words)
    n = len(docs)

    def idf2(word):
        return (math.log((n + 1) / (df[word] + 1)) + 1) ** 2

    qnorm = math.sqrt(sum(idf2(w) for w in query))
    scored = []
    for task, words in docs:
        common = query & words
        if not common or (len(query) >= 3 and len(common) < 2):
            continue
        score = sum(idf2(w) for w in common) / (qnorm * math.sqrt(sum(idf2(w) for w in words)))
        if score >= MIN_SIM:
            scored.append((score, task))
    scored.sort(key=lambda pair: -pair[0])
    return scored[:k]


def calibration(tasks):
    ratios = [t["dur_s"] / 60 / t["estimate_min"]
              for t in tasks if t.get("estimate_min") and not t.get("interrupted")]
    if len(ratios) < 3:
        return None
    within = sum(1 for r in ratios if 0.7 <= r <= 1.3)
    return {"n": len(ratios), "median": pct(ratios, 0.5), "within": within / len(ratios)}


def model_tag(task):
    return " ".join(x for x in (task.get("model"), task.get("effort")) if x) or "?"


QUOTE_LIKE = str.maketrans({c: "'" for c in '"“”„‟«»‹›`´″ʺ˝〃'} | {"[": "(", "]": ")", "⏱": " ", "⏲": " "})


def short(text, n=80):
    """A past prompt as it may be shown to Claude: one line, no control or format characters
    (bidi overrides included), no quotes, brackets or ⏱ that could pass for the block's own text."""
    text = unicodedata.normalize("NFKC", str(text))  # fullwidth ＂［］ become plain ones, then go
    text = "".join(" " if unicodedata.category(c) in ("Cc", "Cf", "Zl", "Zp", "Cs") else c for c in text)
    text = re.sub(r"\s+", " ", text.translate(QUOTE_LIKE)).strip()
    return text if len(text) <= n else text[: n - 1].rstrip() + "…"


# ---------------------------------------------------------------- categories

def load_labels():
    try:
        with open(LABELS, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def guess_category(task):
    """Keyword and tool rules, for tasks nobody labelled. None when nothing matches."""
    text = task.get("prompt", "").lower()
    words = tokens(text)
    scores = Counter()
    for cat, keywords in CAT_WORDS.items():
        for kw in keywords:
            if kw.endswith("*"):
                if any(w.startswith(kw[:-1]) for w in words):
                    scores[cat] += 1
            elif kw in words:
                scores[cat] += 1
    if any(ext in CODE_EXTS for ext in task.get("edit_exts") or {}):
        scores["coding"] += 2
    names = task.get("tool_names") or {}
    if names.get("WebSearch", 0) + names.get("WebFetch", 0) >= 3:
        scores["research"] += 1
    if not scores:
        return None
    best = max(scores.values())
    return next(c for c in CAT_CODES if scores[c] == best)


def resolve_categories(idx, labels=None):
    """Set task["cat"]: the category Claude declared in its estimate line, else the
    label from the one-off classification, else the rules; follow-ups the
    classifier could not place inherit from the task before them."""
    labels = load_labels() if labels is None else labels
    tasks = idx["tasks"]
    done = {}

    def resolve(key, depth=0):
        if key in done:
            return done[key]
        task = tasks.get(key)
        if task is None:
            return None
        cat = task.get("category") or labels.get(key)
        cat = LEGACY_CATS.get(cat, cat)
        if cat not in CAT_CODES:
            inherited = None
            if depth < 30 and task.get("prev_key"):
                inherited = resolve(task["prev_key"], depth + 1)
            guessed = guess_category(task)
            cat = (inherited or guessed) if cat == "followup" else (guessed or inherited)
            cat = cat or "other"
        done[key] = cat
        return cat

    for key in tasks:
        tasks[key]["cat"] = resolve(key)


# ---------------------------------------------------------------- models and effort

def latency_table(tasks, min_calls=30):
    """Mean seconds of model time per API call, by "model|effort"."""
    agg = {}
    for task in tasks:
        for combo, (calls, secs) in (task.get("calls_by") or {}).items():
            acc = agg.setdefault(combo, [0, 0.0])
            acc[0] += calls
            acc[1] += secs
    return {combo: (secs / calls, calls) for combo, (calls, secs) in agg.items()
            if calls >= min_calls and not combo.endswith("|?")}


def step_factor(lat):
    """How much slower one effort step makes a call, averaged over every model
    measured at two or more efforts. Clamped: the data is noisy."""
    logs = []
    for model in {combo.split("|")[0] for combo in lat}:
        measured = sorted((rank, lat["%s|%s" % (model, e)][0])
                          for e, rank in EFFORTS.items() if "%s|%s" % (model, e) in lat)
        for (r1, l1), (r2, l2) in zip(measured, measured[1:]):
            logs.append(math.log(l2 / l1) / (r2 - r1))
    factor = math.exp(sum(logs) / len(logs)) if logs else 1.3
    return min(1.6, max(1.1, factor))


def call_latency(lat, model, effort):
    """(seconds per call, extrapolated?) for a model and effort. A combination never
    measured is extrapolated from the nearest measured effort of the same model."""
    key = "%s|%s" % (model, effort)
    if key in lat:
        return lat[key][0], False
    if effort not in EFFORTS:
        return None, False
    measured = [(rank, lat["%s|%s" % (model, e)][0])
                for e, rank in EFFORTS.items() if "%s|%s" % (model, e) in lat]
    if not measured:
        return None, False
    rank, base = min(measured, key=lambda rb: (abs(rb[0] - EFFORTS[effort]), rb[0]))
    return base * step_factor(lat) ** (EFFORTS[effort] - rank), True


def retime(task, lat, model, effort):
    """The task's duration as if every model call had run on this model and effort.
    Tool time and background agents stay as they were."""
    target, _ = call_latency(lat, model, effort)
    if target is None:
        return None
    dur = task["dur_s"]
    for combo, (calls, secs) in (task.get("calls_by") or {}).items():
        src, _ = call_latency(lat, *combo.split("|", 1))
        if src:
            dur += secs * (target / src - 1)
    sub = task.get("sub")
    if sub and sub.get("busy_s") and sub.get("work_s"):
        # Subagents on the task's own model inherit the new model and effort; one that
        # asked for another model keeps it. Their extra model time stretches the stretch
        # of the task spent waiting on them, in proportion.
        old = new = 0.0
        for combo, (calls, secs) in sub["calls_by"].items():
            m, e = combo.split("|", 1)
            src, _ = call_latency(lat, m, e)
            old += secs
            new += secs * (target / src) if src and m == task.get("model") else secs
        other = max(0.0, sub["work_s"] - old)
        if other + old > 0:
            dur += sub["busy_s"] * ((other + new) / (other + old) - 1)
    return max(1.0, dur)


def session_combo(path):
    """(model, effort) of the last reply in this session's transcript, if any."""
    if not regular_file(path):
        return None
    try:
        with open(path, "rb") as fh:
            size = os.fstat(fh.fileno()).st_size
            for chunk in (2 << 20, 16 << 20):
                fh.seek(max(0, size - chunk))
                for raw in reversed(fh.read().splitlines()):
                    if b'"type":"assistant"' not in raw and b'"type": "assistant"' not in raw:
                        continue
                    rec = load_record(raw)
                    if rec is None:
                        continue
                    model = (rec.get("message") or {}).get("model")
                    effort = rec.get("perTurnEffort") or rec.get("effort")
                    if model and not model.startswith("<") and effort:
                        return short_model(model), effort
                if chunk >= size:
                    break
    except OSError:
        return None
    return None


def app_combo(cli_session=None):
    """(model, effort) picked in the desktop app for this session, from the app's session file.
    Hooks get neither from Claude Code (CLAUDE_EFFORT reaches only the Bash tool), and the
    transcript shows a change only after the next reply, so this is the only source that is
    right on the first prompt and on the prompt right after the user switches."""
    host = os.environ.get("CLAUDE_CODE_HOST_SESSION_ID")
    if host:
        paths = glob.glob(os.path.join(glob.escape(APP_SESSIONS), "*", "*", glob.escape(host) + ".json"))
    elif cli_session and os.path.isdir(APP_SESSIONS):
        # No host id in the environment: find the file that names this CLI session.
        needle = ('"cliSessionId":"%s"' % cli_session).encode()
        paths = []
        for path in glob.glob(os.path.join(glob.escape(APP_SESSIONS), "*", "*", "local_*.json")):
            try:
                if regular_file(path) and os.path.getsize(path) < 16 << 20:
                    with open(path, "rb") as fh:
                        if needle in fh.read().replace(b" ", b""):
                            paths.append(path)
            except OSError:
                continue
    else:
        return None
    for path in paths:
        if not regular_file(path):
            continue
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError, RecursionError):
            continue
        if not isinstance(data, dict):
            continue
        if cli_session and data.get("cliSessionId") not in (None, cli_session):
            continue
        model, effort = data.get("model"), data.get("effort")
        if model and effort and not str(model).startswith("<"):
            return short_model(model), effort
    return None


def latest_combo(tasks):
    dated = [t for t in tasks if t.get("model") and t.get("effort")]
    if not dated:
        return None
    last = max(dated, key=lambda t: t["start_ts"])
    return last["model"], last["effort"]


def ladder(lat, model):
    parts = []
    for effort in sorted(EFFORTS, key=EFFORTS.get):
        secs, guessed = call_latency(lat, model, effort)
        if secs is not None:
            parts.append("%s %s%.0f s" % (effort, "~" if guessed else "", secs))
    return ", ".join(parts)


# ---------------------------------------------------------------- predictor

def weighted_median(pairs):
    pairs = sorted(pairs)
    total = sum(w for _, w in pairs)
    acc = 0.0
    for value, weight in pairs:
        acc += weight
        if acc >= total / 2:
            return value
    return None


class Predictor:
    """Raw time estimate for a request: the median of its category, pulled toward the
    similar past tasks as much as they really match, all re-timed for a model and effort.
    Built once, then queried many times (the calibration asks it about hundreds of tasks)."""

    def __init__(self, work, lat):
        self.work, self.lat = work, lat
        self.docs = [(t, tokens(t["prompt"])) for t in work]
        df = Counter()
        for _, words in self.docs:
            df.update(words)
        self.n = len(self.docs)
        self.idf2 = {w: (math.log((self.n + 1) / (c + 1)) + 1) ** 2 for w, c in df.items()}
        self.norms = [math.sqrt(sum(self.idf2[w] for w in words)) or 1.0 for _, words in self.docs]
        self.by_cat = {}
        for task in work:
            self.by_cat.setdefault(task.get("cat"), []).append(task)
        self.medians = {}

    def similar(self, text, k=5, exclude=None):
        query = tokens(text)
        if not query:
            return []
        unseen = (math.log(self.n + 1) + 1) ** 2
        qnorm = math.sqrt(sum(self.idf2.get(w, unseen) for w in query))
        scored = []
        for (task, words), norm in zip(self.docs, self.norms):
            if task["key"] == exclude:
                continue
            common = query & words
            if not common or (len(query) >= 3 and len(common) < 2):
                continue
            score = sum(self.idf2[w] for w in common) / (qnorm * norm)
            if score >= MIN_SIM:
                scored.append((score, task))
        scored.sort(key=lambda pair: -pair[0])
        return scored[:k]

    def category_median(self, cat, model, effort, agents=None):
        """Median re-timed duration of the category; agents=True/False keeps only the tasks
        that did / did not use subagents (when there are enough of them)."""
        key = (cat, model, effort, agents)
        if key not in self.medians:
            group = self.by_cat.get(cat) or []
            if len(group) < 5:
                group = self.work
            if agents is not None:
                kept = [t for t in group if (t["agents"] > 0) == agents]
                if len(kept) < 5:
                    kept = [t for t in self.work if (t["agents"] > 0) == agents]
                group = kept if len(kept) >= 5 else group
            values = [v for v in (retime(t, self.lat, model, effort) for t in group) if v]
            self.medians[key] = pct(values, 0.5)
        return self.medians[key]

    def agent_odds(self, text, cat, sims):
        """Chance that the request will need subagents: the share of the closest past
        requests that used them, else the category's share; agent words push it up."""
        if sims:
            total = sum(s for s, _ in sims)
            odds = sum(s for s, t in sims if t["agents"] > 0) / total
        else:
            group = self.by_cat.get(cat) or self.work
            odds = sum(1 for t in group if t["agents"] > 0) / max(1, len(group))
        words = tokens(text)
        if any((w.startswith(k[:-1]) if k.endswith("*") else w == k) for w in words for k in AGENT_WORDS):
            odds = max(odds, 0.6)
        return odds

    def raw(self, text, model, effort, exclude=None):
        """(seconds, category guessed from the words, similar tasks, chance of subagents)."""
        cat = guess_category({"prompt": text})
        sims = self.similar(text, exclude=exclude)
        odds = self.agent_odds(text, cat, sims)
        agents = odds >= 0.5
        estimate = self.category_median(cat, model, effort, agents)
        matching = [(s, t) for s, t in sims if (t["agents"] > 0) == agents] or sims
        values = [(v, s) for v, s in ((retime(t, self.lat, model, effort), s) for s, t in matching) if v]
        if values:
            from_similar = weighted_median(values)
            trust = min(1.0, sims[0][0] / STRONG_SIM)  # how much the best match really matches
            if estimate:
                estimate = math.exp((1 - trust) * math.log(estimate) + trust * math.log(from_similar))
            else:
                estimate = from_similar
        return estimate, cat, sims, odds


def build_predictor(idx):
    tasks = finished_tasks(idx)
    resolve_categories(idx)
    work = [t for t in tasks if is_work(t)]
    lat = latency_table(tasks)
    return Predictor(work, lat), work, lat


def calibrate(idx, last_n=300):
    """Ask the predictor about each of the last tasks as if it were new (itself left out
    of the similar ones) and keep real/predicted: the median is the correction factor."""
    pred, work, _ = build_predictor(idx)
    by_group, ratios = {}, []
    # Only the most recent tasks are scored, so the Stop hook stays fast on a long history.
    recent = sorted((t for t in work if t.get("model") and t.get("effort")), key=lambda t: t["start_ts"])
    for task in recent[-2 * last_n:]:
        guess, _, _, odds = pred.raw(task["prompt"], task["model"], task["effort"], exclude=task["key"])
        if guess:
            ratios.append(task["dur_s"] / guess)
            by_group.setdefault(range_group(odds >= 0.5, task), []).append(task["dur_s"] / guess)
    ratios = ratios[-last_n:]
    if len(ratios) < 20:
        return None
    factor = pct(ratios, 0.5)
    groups = {}
    for g, rs in by_group.items():
        rs = rs[-last_n:]
        if len(rs) >= 20:
            # The quartiles give the range that holds the real time one time out of two.
            groups[g] = {"factor": pct(rs, 0.5), "q25": pct(rs, 0.25), "q75": pct(rs, 0.75), "n": len(rs)}
    data = {
        "factor": factor, "q25": pct(ratios, 0.25), "q75": pct(ratios, 0.75),
        "within_2x": sum(1 for r in ratios if 0.5 <= r / factor <= 2) / len(ratios),
        "n": len(ratios), "work_tasks": len(work), "at": time.time(), "groups": groups,
    }
    write_json(PREDICTOR, data, indent=1)
    return data


def calibrate_in_background():
    """The Stop hook starts the calibration as its own process and returns at once: on a long
    history it takes longer than a hook should."""
    import subprocess
    try:
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "calibrate", "--no-update"], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        pass


def load_predictor():
    try:
        with open(PREDICTOR, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def fmt_words(seconds):
    """Real duration in words: "40 seconds", "3 minutes", "1.5 hours"."""
    if seconds < 90:
        return "%d seconds" % round(seconds)
    if seconds < 90 * 60:
        mins = round(seconds / 60)
        return "1 minute" if mins == 1 else "%d minutes" % mins
    return "%.1f hours" % (seconds / 3600)


# "likely 4 to 24 min", "likely 40 s to 3 min"; older versions wrote "probabile tra 4 e 24 min".
RANGE_RE = re.compile(r"(?:\blikely|\btra)[ \t]+~?(\d{1,9}(?:[.,]\d{1,3})?)[ \t]*(s|min|h|ore)?[ \t]+(?:to|e)[ \t]+"
                      r"~?(\d{1,9}(?:[.,]\d{1,3})?)[ \t]*(s|min|h|ore)\b")
UNIT_S = {"s": 1, "min": 60, "h": 3600, "ore": 3600}


def parse_range(text):
    """(low, high) in seconds from "likely 4 to 24 min" in the first ⏱ line, or None."""
    m = RANGE_RE.search(estimate_line(text))
    if not m:
        return None
    hi_unit = UNIT_S[m.group(4)]
    lo_unit = UNIT_S[m.group(2)] if m.group(2) else hi_unit
    lo, hi = float(m.group(1).replace(",", ".")) * lo_unit, float(m.group(3).replace(",", ".")) * hi_unit
    return [lo, hi] if 0 <= lo <= hi <= EST_MAX_MIN * 60 else None


def fmt_range(lo, hi):
    """ "4 to 24 min", "40 s to 3 min", "20 to 45 s": the likely range in the line."""
    lo, hi = max(5.0, lo), max(lo + 1, hi)
    if hi < 90:
        return "%d to %d s" % (round(lo), round(hi))
    if hi < 90 * 60:
        if lo < 60:
            return "%d s to %d min" % (round(lo), round(hi / 60))
        return "%d to %d min" % (max(1, round(lo / 60)), max(2, round(hi / 60)))
    hours = ("%.1f" % (hi / 3600)).replace(".0", "")
    if lo < 90 * 60:
        return "%d min to %s h" % (max(1, round(lo / 60)), hours)
    return "%s to %s h" % (("%.1f" % (lo / 3600)).replace(".0", ""), hours)


def shown_prompt(task, n):
    """A past prompt as any output shows it: cleaned by short(), automated runs not shown at all."""
    return "(an automated claude -p run)" if is_headless(task) else short(task.get("prompt") or "", n)


def is_headless(task):
    """A `claude -p` run (tests, scripts). Older index entries have no flag: a session run in
    a temporary folder counts as one."""
    if task.get("headless"):
        return True
    path = task.get("file") or ""
    return "/-private-tmp-" in path or "/-tmp-" in path


def range_group(with_agents, task=None):
    """Which spread applies: subagents, headless test runs, or the user's real tasks.
    task=None means the prompt being estimated right now."""
    if with_agents:
        return "agents"
    if is_headless(task) if task is not None else os.environ.get("CLAUDE_CODE_ENTRYPOINT") == "sdk-cli":
        return "test"
    return "real"


def group_corr(corr, group):
    """The correction of one group (factor and quartiles of real/predicted), else the global one."""
    if not corr:
        return None
    g = (corr.get("groups") or {}).get(group)
    return dict(corr, **g) if g else corr


def fmt_estimate(seconds):
    """For the estimate line: "~40 s" under a minute, else whole minutes or hours."""
    if seconds < 55:
        return "~%d s" % max(10, round(seconds / 5) * 5)
    if seconds < 90 * 60:
        return "~%d min" % max(1, round(seconds / 60))
    return ("~%.1f h" % (seconds / 3600)).replace(".0 h", " h")


# ---------------------------------------------------------------- estimate block

def main_combos(work, effort=None, k=4):
    """The models used most in the last 200 tasks, each at the given effort or at its usual one."""
    recent = sorted(work, key=lambda t: t["start_ts"])[-200:]
    models = Counter(t["model"] for t in recent if t.get("model"))
    out = []
    for model, _ in models.most_common(k):
        usual = Counter(t["effort"] for t in recent if t.get("model") == model and t.get("effort"))
        out.append((model, effort or (usual.most_common(1)[0][0] if usual else "medium")))
    return out


def estimate_block(text, idx, current=None, low_effort="low", source="this session's last reply",
                   effort_hint=None, info=None):
    """The [task-eta] block for a prompt. If info is a dict, it also gets the numbers of the
    suggested estimate (seconds, likely range, model and effort), for the live file."""
    tasks = finished_tasks(idx)
    hide = os.environ.get("TASK_ETA_EXCLUDE")
    if hide:
        # Benchmarks: keep their own earlier runs out of the "similar tasks".
        tasks = [t for t in tasks if hide not in (t.get("file") or "")]
    work = [t for t in tasks if is_work(t)]
    if len(work) < 5:
        return None
    resolve_categories(idx)
    lat = latency_table(tasks)
    candidates = [current] if current else main_combos(work, effort_hint)
    if not candidates:
        return None
    model, effort = candidates[0]
    if not current:
        source = "unknown: no reply in this session yet, the lines below cover the main models"
    combos = [(model, effort)]
    if call_latency(lat, model, effort)[0] is None:
        return ("[task-eta] No timing data for %s yet: estimate from your own count of the steps, "
                "and open the reply with \"⏱ Estimated time with %s %s: ~N min\"."
                % (model, model, effort))

    head = " | ".join("%s %s" % c for c in combos)
    low_note = ""
    if len(combos) > 1 and call_latency(lat, model, low_effort)[1]:
        low_note = " %s was never used: its times are extrapolated from the other efforts." % low_effort
    lines = [
        "[task-eta] Real durations of past Claude Code tasks on this machine, re-timed as if every "
        "model call had run on a given model and effort (wall clock from prompt to done, background "
        "agents included, waits for the user excluded; tool time is kept as it was).",
        "- Now: %s %s (from %s). Model seconds per call for %s: %s.%s"
        % (model, effort, source, model, ladder(lat, model), low_note),
        "- By category, median (p75), re-timed for %s:" % head,
    ]
    by_cat = {}
    for task in work:
        by_cat.setdefault(task["cat"], []).append(task)
    for cat in CAT_CODES:
        group = by_cat.get(cat, [])
        if len(group) < 5:
            continue
        cells = []
        for m, e in combos:
            vals = [v for v in (retime(t, lat, m, e) for t in group) if v]
            cells.append("%s (%s)" % (fmt(pct(vals, 0.5)), fmt(pct(vals, 0.75))))
        lines.append("  %s n=%d: %s" % (cat, len(group), " | ".join(cells)))
    pred = Predictor(work, lat)
    raw, cat, sims, odds = pred.raw(text, model, effort)
    with_agents = odds >= 0.5
    corr = group_corr(load_predictor(), range_group(with_agents))
    if info is not None and raw:
        # The same numbers as the "Suggested estimate" line: with no reply in the session yet,
        # the first model line, which is the model and effort used most lately.
        factor = corr["factor"] if corr else 1.0
        info.update(model=model, effort=effort, model_known=bool(current), category=cat,
                    estimate_s=round(raw * factor), estimate_label=fmt_estimate(raw * factor),
                    low_s=round(raw * corr["q25"]) if corr else None,
                    high_s=round(raw * corr["q75"]) if corr else None)
    if not current and corr:
        lines.append("- Suggested estimate by model (use the line of the model you are; effort %s):"
                     % ("from the session setting" if effort_hint else "the one each model usually runs at"))
        for m, e in candidates:
            r = pred.raw(text, m, e)[0]
            if r:
                lines.append("  %s %s: %s (likely %s)" % (m, e, fmt_estimate(r * corr["factor"]),
                                                         fmt_range(r * corr["q25"], r * corr["q75"])))
    elif raw:
        if corr:
            lines.append("- Suggested estimate: %s (likely %s to %s). Raw %s from the %s median and the similar "
                         "tasks below, re-timed for %s %s, times %.2f: the real/predicted ratio measured on your "
                         "last %d tasks (corrected predictions within 2x of the real time: %d%%)." % (
                             fmt_estimate(raw * corr["factor"]), fmt(raw * corr["q25"]), fmt(raw * corr["q75"]),
                             fmt(raw), cat or "overall", model, effort, corr["factor"], corr["n"],
                             round(corr["within_2x"] * 100)))
        else:
            lines.append("- Suggested estimate: %s (not calibrated yet)." % fmt_estimate(raw))
    if sims:
        lines.append("- Most similar past requests, re-timed for %s:" % head)
        for score, task in sims:
            cells = " | ".join(fmt(retime(task, lat, m, e)) for m, e in combos)
            lines.append('  [%s] %s (was %s on %s, %d tool calls%s): "%s"' % (
                task["cat"], cells, fmt(task["dur_s"]), model_tag(task), task["tools"],
                ", %d agents" % task["agents"] if task["agents"] else "",
                shown_prompt(task, 70)))
    cal = calibration(tasks)
    if cal:
        lines.append("- Your own past estimates (n=%d): real/estimate median %.1fx. For information only: "
                     "the suggestion above is already corrected, do not correct it again."
                     % (cal["n"], cal["median"]))
    me = "%s %s" % (shlex.quote(sys.executable), shlex.quote(os.path.abspath(__file__)))
    lines.append("If the request needs tools, open the reply with the ⏱ line below, before any tool call, "
                 "using the suggested number unless the request plainly needs far more or far fewer steps. "
                 "Write only the line: no reasons, no mention of the hook or of how the number was found. "
                 "No line for a plain answer that needs no tools. As the last tool call of the task, run "
                 "`%s elapsed` and end the reply with the line it prints, unchanged. In a long task, an "
                 "intermediate update may include the line printed by `%s eta`." % (me, me))
    suffix = ", with subagents" if with_agents else ""
    lines.append("- Subagents: %s (%d%% of the closest past requests used them, or the request names that kind "
                 "of work). The estimate is built from past tasks %s them." % (
                     "likely needed" if with_agents else "not expected", round(odds * 100),
                     "that used" if with_agents else "without"))
    if current and raw and corr:
        lines.append("⏱ Estimated time with %s %s: %s (likely %s%s)" % (
            model, effort, fmt_estimate(raw * corr["factor"]), fmt_range(raw * corr["q25"], raw * corr["q75"]), suffix))
    elif current:
        lines.append("⏱ Estimated time with %s %s: ~N min%s" % (model, effort, " (with subagents)" if with_agents else ""))
    else:
        lines.append("⏱ Estimated time with <your model> <your effort>: <the number and the likely range on "
                     "your model's line, in brackets%s>" % suffix)
    if sims and sims[0][0] >= STRONG_SIM:
        best = sims[0][1]
        lines.append("A past request matches closely, so you may add this sentence right after the line, as is:")
        lines.append("A similar task took %s." % fmt_words(best["dur_s"]))
    return "\n".join(lines)


# ---------------------------------------------------------------- live files (desktop widget)

def clip(text, n):
    return text if len(text) <= n else text[: n - 1].rstrip() + "…"


def fmt_clock(seconds):
    """Compact elapsed time: "45s", "2m10s", "1h05m"."""
    s = int(round(seconds or 0))
    if s < 60:
        return "%ds" % s
    if s < 3600:
        return "%dm%02ds" % (s // 60, s % 60)
    return "%dh%02dm" % (s // 3600, s % 3600 // 60)


def live_path(session, start_ts=None):
    name = session if start_ts is None else "%s-%d" % (session, start_ts)
    return os.path.join(LIVE_DIR, re.sub(r"[^\w.-]", "_", name, flags=re.ASCII) + ".json")


def read_live(path):
    if not regular_file(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else None
    except (OSError, ValueError, RecursionError):
        return None


def write_live(path, data):
    """Atomic: the widget reads these files every 2 seconds."""
    os.makedirs(LIVE_DIR, exist_ok=True)
    data["updated_ts"] = round(time.time(), 3)
    tmp = os.path.join(LIVE_DIR, ".%s.%d.tmp" % (os.path.basename(path), os.getpid()))
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def quietly(fn, *args):
    """The hooks must never fail or print because of the live files."""
    try:
        if not os.path.exists(LIVE_OFF):
            fn(*args)
    except Exception:
        pass


def input_path(session):
    """Marker of a session waiting for the user: a question, a plan or a permission to
    approve, or a last reply that asks something. A PostToolUse hook (plain sh, no Python)
    deletes it as soon as a tool runs again; the next prompt deletes it too."""
    return os.path.join(LIVE_DIR, re.sub(r"[^\w.-]", "_", str(session), flags=re.ASCII) + ".input")


def clear_input(session):
    try:
        os.remove(input_path(session))
    except OSError:
        pass


def asks_user(text):
    """True if a reply ends by asking the user something (the ⏱ lines aside)."""
    lines = [l.strip() for l in (text or "").splitlines()]
    lines = [re.sub(r"[*_`\s]+$", "", l) for l in lines if l and not l.startswith("⏱")]
    return any(l.endswith("?") for l in lines[-2:])


# Background work: launched by a tool, it reports back with a <task-notification> that names
# the tool call. Until then the turn is over but the task is not. Only real launches count:
# a Bash or Agent call with run_in_background, Monitor, Workflow, or an Agent call whose
# result opens with the async launch line. The same words in another tool's output (a grep
# over transcripts, say) are not a launch: that marked a finished task "in background".
BG_TOOLS = ("Monitor", "Workflow")
BG_AGENT_TOOLS = ("Agent", "Task")
BG_AGENT_LAUNCHED = "Async agent launched"
BG_NOTIFIED = re.compile(r"<tool-use-id>(toolu_\w+)</tool-use-id>")


def result_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return ""


def background_jobs(path, since):
    """Descriptions of the background jobs launched since `since` that have not reported back."""
    uses, launched, notified = {}, {}, set()
    if not regular_file(path):
        return []
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return []
    with fh:
        for line in fh:
            if "<task-notification" in line:
                notified.update(BG_NOTIFIED.findall(line))
            if '"tool_use"' not in line and '"tool_result"' not in line:
                continue
            rec = load_record(line)
            if rec is None or rec.get("isSidechain") or (parse_ts(rec.get("timestamp")) or 0) < since - 1:
                continue
            content = (rec.get("message") or {}).get("content")
            for block in content if isinstance(content, list) else []:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_use":
                    inp = block.get("input") if isinstance(block.get("input"), dict) else {}
                    name = str(block.get("name") or "")
                    desc = str(inp.get("description") or name)
                    uses[block.get("id")] = (name, desc)
                    if inp.get("run_in_background") is True or name in BG_TOOLS:
                        launched[block.get("id")] = desc
                elif block.get("type") == "tool_result":
                    name, desc = uses.get(block.get("tool_use_id"), ("", ""))
                    if (name in BG_AGENT_TOOLS
                            and result_text(block.get("content")).lstrip().startswith(BG_AGENT_LAUNCHED)):
                        launched[block.get("tool_use_id")] = desc
    return [desc for tid, desc in launched.items() if tid not in notified]


def turn_state(path, since, tail=256 * 1024):
    """(interrupted, last) for the task that started at `since`: whether the user interrupted
    Claude after it (Esc ends the task, no Stop comes), and when Claude last wrote something.
    Unreadable transcript: (True, None), a new task is the safer guess."""
    if not regular_file(path):
        return True, None
    try:
        with open(path, "rb") as fh:
            fh.seek(max(0, os.path.getsize(path) - tail))
            lines = fh.read().decode("utf-8", "replace").splitlines()[1:]
    except (OSError, TypeError):
        return True, None
    interrupted, last = False, None
    for line in lines:
        if '"assistant"' not in line and INTERRUPT not in line:
            continue
        rec = load_record(line)
        if rec is None:
            continue
        ts = parse_ts(rec.get("timestamp")) or 0
        if ts <= since:
            continue
        if rec.get("type") == "assistant":
            last = max(last or 0, ts)
        elif rec.get("type") == "user" and (INTERRUPT in record_text(rec)
                                            or INTERRUPT in result_text((rec.get("message") or {}).get("content"))):
            interrupted = True
    return interrupted, last


def live_start(data, prompt, info, combo):
    """hook-prompt: the session's new task, running. A finished task before it is kept
    under its own name, so the widget can still show it."""
    session = data.get("session_id")
    if not session:
        return
    clear_input(session)
    path = live_path(session)
    old = read_live(path)
    if old and old.get("status") == "running" and old.get("start_ts"):
        # Typed while Claude is still working (no Stop since the task began, no interrupt, Claude
        # active in the last STALE_TURN_S): the index keeps it in the same task, so does the widget.
        interrupted, last = turn_state(data.get("transcript_path"), old["start_ts"])
        if not interrupted and last and time.time() - last < STALE_TURN_S:
            return
    if old and old.get("status") in ("done", "background") and old.get("start_ts"):
        if old["status"] == "background":
            # A new prompt while jobs still run: the index gives their time to the new task.
            old.update(status="done", end_ts=old.get("end_ts") or round(time.time(), 3))
            write_live(path, old)
        os.replace(path, live_path(session, old["start_ts"]))
    transcript = data.get("transcript_path")
    try:
        offset = os.path.getsize(transcript)  # the widget reads Claude's ⏱ line from here on
    except (OSError, TypeError):
        offset = None
    write_live(path, {
        "version": 1,
        "session": session,
        "cwd": os.path.basename((data.get("cwd") or os.getcwd()).rstrip("/")),
        "transcript": transcript,
        "transcript_offset": offset,
        # sdk-cli = a headless `claude -p` run (tests, scripts): the widget hides them by default.
        "entrypoint": os.environ.get("CLAUDE_CODE_ENTRYPOINT"),
        "prompt": clip(prompt, 80),
        "start_ts": round(time.time(), 3),
        "model": info.get("model") or (combo[0] if combo else None),
        "effort": info.get("effort") or (combo[1] if combo else os.environ.get("CLAUDE_EFFORT")),
        "model_known": bool(combo),
        "category": info.get("category"),
        "estimate_s": info.get("estimate_s"),
        "estimate_label": info.get("estimate_label"),
        "low_s": info.get("low_s"),
        "high_s": info.get("high_s"),
        "estimate_min": None,
        "idle_s": 0,
        "status": "running",
    })


def live_resume(data, own=True):
    """hook-prompt on an agent notification or a message from another session: the
    finished task goes on (the index counts it as the same task). The pause since its end
    counts only when own work of this session woke it up (see FOREIGN_WAKES)."""
    clear_input(data.get("session_id") or "")
    path = live_path(data.get("session_id") or "")
    live = read_live(path)
    if not live or live.get("status") not in ("done", "background") or not live.get("start_ts"):
        return
    now = time.time()
    end = live.get("end_ts") or now
    # Elapsed = now - start - idle_s: keep the time the index left out so far, and the pause
    # since the end when the index does not count it either.
    idle = max(0.0, end - live["start_ts"] - (live.get("dur_s") or 0))
    if now - end > IDLE_CAP_S or not own:
        idle += now - end
    live.update(status="running", idle_s=round(idle, 1), resumed_ts=round(now, 3))
    live.pop("end_ts", None)
    write_live(path, live)


def live_finish(data, tasks):
    """hook-stop: the session's task is done, with its real duration from the index."""
    session = data.get("session_id")
    if not session:
        return
    path = live_path(session)
    live = read_live(path)
    now = time.time()
    task = tasks[-1] if tasks else None
    if live and task and task["start_ts"] > live.get("start_ts", 0) + 60:
        # The live file is from an earlier prompt (the hook missed this one).
        if live.get("status") == "done":
            os.replace(path, live_path(session, live["start_ts"]))
        live = None
    if live is None:
        if task is None or now - task["start_ts"] > 6 * 3600:
            return
        live = {"version": 1, "session": session, "cwd": task.get("cwd"),
                "transcript": data.get("transcript_path"), "prompt": clip(task["prompt"], 80),
                "start_ts": task["start_ts"], "category": None, "estimate_s": None,
                "estimate_label": None, "low_s": None, "high_s": None, "idle_s": 0}
    if task:
        live["start_ts"] = min(live["start_ts"], task["start_ts"])
        live["dur_s"] = task["dur_s"]
        live["estimate_min"] = task.get("estimate_min")
        if task.get("model"):
            live.update(model=task["model"], effort=task.get("effort"), model_known=True)
        live["category"] = task.get("category") or guess_category(task) or live.get("category")
    else:
        live["dur_s"] = round(max(0.0, now - live["start_ts"] - (live.get("idle_s") or 0)), 1)
    # Jobs still running in the background: the turn is over, the task is not. The widget keeps
    # the clock going (elapsed = now - start - idle_s) until their notification wakes Claude.
    jobs = background_jobs(data.get("transcript_path"), live["start_ts"])
    live.update(status="background" if jobs else "done", end_ts=round(now, 3),
                bg_jobs=[clip(j, 60) for j in jobs][:5],
                idle_s=round(max(0.0, now - live["start_ts"] - live["dur_s"]), 1))
    write_live(path, live)
    clear_input(session)
    last = data.get("last_assistant_message")
    if isinstance(last, str) and asks_user(last):
        write_live(input_path(session), {"kind": "reply", "detail": "", "ts": round(now, 3)})
    live_prune(now)


def live_automated(live):
    """A headless `claude -p` run (tests, scripts): older files have no entrypoint, so a
    session in a temporary folder counts as one, as in the widget."""
    if live.get("entrypoint"):
        return live["entrypoint"] == "sdk-cli"
    return any(part in (live.get("transcript") or "") for part in ("/-private-tmp-", "/-tmp-"))


def live_prune(now):
    """Keep the last LIVE_KEEP_DONE finished tasks, counted apart for the user's sessions and
    for automated runs (a round of 100 tests must not push the user's tasks out), and drop
    anything older than a day."""
    done = {False: [], True: []}
    for path in glob.glob(os.path.join(glob.escape(LIVE_DIR), "*.json")):
        live = read_live(path) if regular_file(path) else None
        if not is_live_file(live):
            continue  # not written by task-eta: never deleted
        try:
            if now - os.path.getmtime(path) > LIVE_MAX_AGE_S:
                os.remove(path)
                continue
        except OSError:
            continue
        if live.get("status") == "done":
            done[live_automated(live)].append((live.get("end_ts") or 0, path))
    for group in done.values():
        for _, path in sorted(group, reverse=True)[LIVE_KEEP_DONE:]:
            try:
                os.remove(path)
            except OSError:
                pass
    base = glob.escape(LIVE_DIR)
    tmps = [p for p in glob.glob(os.path.join(base, ".*.tmp")) if ".json." in p or ".input." in p]
    for path in tmps + glob.glob(os.path.join(base, "*.input")):
        if path.endswith(".input") and "kind" not in (read_live(path) or {}):
            continue
        try:
            if now - os.path.getmtime(path) > (3600 if path.endswith(".tmp") else LIVE_MAX_AGE_S):
                os.remove(path)
        except OSError:
            pass


def is_live_file(live):
    """A live file written by task-eta (the only kind live_prune may delete)."""
    return isinstance(live, dict) and live.get("version") == 1 and "start_ts" in live and "session" in live


def live_tasks(now):
    """(running, finished) from live/, newest first. A running task whose transcript has
    been silent for SILENCE_CAP_S is stale: interrupted, or waiting on the user."""
    running, done = [], []
    for path in glob.glob(os.path.join(glob.escape(LIVE_DIR), "*.json")):
        live = read_live(path) if regular_file(path) else None
        if not live or not live.get("start_ts"):
            continue
        if live.get("session") and path == live_path(live["session"]):
            live["needs_input"] = read_live(input_path(live["session"]))
        if live.get("status") in ("running", "background"):
            live["elapsed_s"] = round(max(0.0, now - live["start_ts"] - (live.get("idle_s") or 0)), 1)
            try:
                live["quiet_s"] = round(now - os.path.getmtime(live.get("transcript") or ""), 1)
            except OSError:
                live["quiet_s"] = None
            live["stale"] = live["quiet_s"] is not None and live["quiet_s"] > SILENCE_CAP_S
            running.append(live)
        else:
            done.append(live)
    running.sort(key=lambda t: -t["start_ts"])
    done.sort(key=lambda t: -(t.get("end_ts") or 0))
    return running, done


# ---------------------------------------------------------------- commands

def read_hook_input():
    """The JSON object Claude Code passes to a hook; anything else counts as empty."""
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return {}
    return data if isinstance(data, dict) else {}


def cmd_hook_prompt():
    data = read_hook_input()
    if os.environ.get("TASK_ETA_DEBUG"):
        with open(os.environ["TASK_ETA_DEBUG"], "w") as fh:
            json.dump({"input_keys": sorted(data), "model_fields": {k: v for k, v in data.items() if "model" in k or "effort" in k},
                       "env": {k: v for k, v in os.environ.items() if "EFFORT" in k or "MODEL" in k}}, fh, indent=1)
    raw = data.get("prompt")
    raw = raw.lstrip() if isinstance(raw, str) else ""
    body = wake_body(raw)  # the app may put reminders in front of a wake-up
    if body.startswith(SKIP_PROMPTS):
        quietly(live_resume, data, own_wake(body))
        return
    prompt = spawn_prompt(raw) or clean_prompt(raw)
    if not prompt:
        return
    combo = session_combo(data.get("transcript_path"))
    source = "this session's last reply"
    effort = os.environ.get("CLAUDE_EFFORT")
    picked = app_combo(data.get("session_id"))
    if picked:
        # The desktop app's choice for this session, already updated when the user switches.
        combo, source = picked, "the model and effort picked in the app for this session"
    elif effort and combo:
        # Not set for hooks in the desktop app (verified 2026-10-20); kept for other hosts.
        combo = (combo[0], effort)
        source = "the session's effort setting, model from this session's last reply"
    info = {}
    block = estimate_block(prompt, load_index(), combo, source=source, effort_hint=effort, info=info)
    if block:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit", "additionalContext": block}}))
        sys.stdout.flush()
    quietly(live_start, data, prompt, info, combo)


# Tools that stop and wait for the user, and what the widget calls the wait.
INPUT_TOOLS = {"AskUserQuestion": "question", "ExitPlanMode": "plan",
               "mcp__ccd_session__start_session": "choice"}
INPUT_NOTICES = {"permission_prompt": "permission", "elicitation_dialog": "question"}


def cmd_hook_input():
    """Claude is waiting for the user: a question or a plan (PreToolUse), a permission dialog
    (PermissionRequest, Notification). Writes the session's .input marker for the widget."""
    data = read_hook_input()
    session = data.get("session_id")
    event = data.get("hook_event_name")
    tool = data.get("tool_name") or ""
    inp = data.get("tool_input") or {}
    detail = ""
    if event == "PreToolUse":
        kind = INPUT_TOOLS.get(tool)
        if tool == "mcp__ccd_session__start_session" and inp.get("initiation") != "offer":
            kind = None  # only an offer waits for the user's answer
        questions = inp.get("questions") if isinstance(inp.get("questions"), list) else []
        if questions and isinstance(questions[0], dict):
            detail = questions[0].get("question") or ""
        detail = detail or inp.get("title") or ""
    elif event == "PermissionRequest":
        kind, detail = "permission", tool.split("__")[-1]
    elif event == "Notification":
        kind, detail = INPUT_NOTICES.get(data.get("notification_type")), data.get("message") or ""
    else:
        kind = None
    if session and kind:
        quietly(write_live, input_path(session), {"kind": kind, "detail": clip(str(detail), 120),
                                                  "ts": round(time.time(), 3)})


def cmd_hook_stop():
    data = read_hook_input()
    path = data.get("transcript_path")
    if not regular_file(path):
        return
    since = history_since()
    tasks = [t for t in parse_transcript(path) if t["start_ts"] >= since]
    idx = load_index()
    for task in tasks:
        idx["tasks"][task["key"]] = task
    st = os.stat(path)
    idx["files"][path] = [round(st.st_mtime, 3), st.st_size]
    save_index(idx)
    quietly(live_finish, data, tasks)
    corr = load_predictor()
    work_now = sum(1 for t in finished_tasks(idx) if is_work(t))
    if (not corr or abs(work_now - corr.get("work_tasks", 0)) >= 5
            or time.time() - corr.get("at", 0) > 6 * 3600):
        calibrate_in_background()
    if not tasks:
        return
    last = tasks[-1]
    if last.get("estimate_min"):
        delta = (last["dur_s"] / 60 / last["estimate_min"] - 1) * 100
        bits = ["⏱ Estimate ~%g min · actual %s (%+d%%)" % (last["estimate_min"], fmt(last["dur_s"]), round(delta))]
        bits.append(LEGACY_CATS.get(last.get("category"), last.get("category")) or guess_category(last) or "other")
        bits.append(model_tag(last))
        print(json.dumps({"systemMessage": " · ".join(bits)}))


def cmd_elapsed():
    """Real time of the task in progress, for Claude to print at the end of its reply:
    the desktop app records the Stop hook's message but does not show it in the chat."""
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID")
    paths = glob.glob(os.path.join(glob.escape(PROJECTS), "*", "%s.jsonl" % glob.escape(sid))) if sid else []
    if not paths:
        paths = sorted(glob.glob(os.path.join(glob.escape(PROJECTS), "*", "*.jsonl")), key=os.path.getmtime)[-1:]
    if not paths:
        return
    tasks = parse_transcript(paths[0])
    if not tasks:
        return
    idx = load_index()
    since = history_since()
    for task in tasks:
        if task["start_ts"] >= since:
            idx["tasks"][task["key"]] = task
    save_index(idx)
    last = tasks[-1]
    line = "⏱ Actual time: %s" % fmt(last["dur_s"])
    rng = last.get("est_range")
    if rng:
        inside = rng[0] <= last["dur_s"] <= rng[1]
        line += " (likely %s: %s)" % (fmt_range(*rng), "inside" if inside else "outside")
    elif last.get("estimate_min"):
        delta = (last["dur_s"] / 60 / last["estimate_min"] - 1) * 100
        line += " (estimated ~%g min, %+d%%)" % (last["estimate_min"], round(delta))
    print(line)


def cmd_status(args):
    """Tasks in progress and the last 10 finished ones, from live/ only (fast)."""
    now = time.time()
    running, done = live_tasks(now)
    done = done[:10]
    if "--json" in args:
        print(json.dumps({"now": round(now, 3), "live_dir": LIVE_DIR, "running": running,
                          "finished": done}, ensure_ascii=False, indent=1))
        return

    def est(t):
        if t.get("estimate_min"):
            return "est. %g min" % t["estimate_min"]
        if t.get("estimate_label"):
            rng = " (%s-%s)" % (fmt(t["low_s"]), fmt(t["high_s"])) if t.get("low_s") is not None else ""
            return "est. %s%s" % (t["estimate_label"], rng)
        return "no estimate"

    def tag(t):
        return " ".join(x for x in (t.get("model"), t.get("effort")) if x) or "?"

    out = ["Running: %d" % len(running)]
    for t in running:
        out.append("  %-7s %-26s %-16s %-18s %s%s" % (
            fmt_clock(t["elapsed_s"]), est(t), tag(t), clip(t.get("cwd") or "", 18), short(t.get("prompt") or "", 80),
            "  (quiet for %s)" % fmt_clock(t["quiet_s"]) if t.get("stale") else ""))
    out.append("Finished, last %d:" % len(done))
    for t in done:
        out.append("  %s  %-7s / %-24s %-16s %-18s %s" % (
            datetime.fromtimestamp(t.get("end_ts") or t["start_ts"]).strftime("%H:%M"),
            fmt_clock(t.get("dur_s")), est(t), tag(t), clip(t.get("cwd") or "", 18), short(t.get("prompt") or "", 80)))
    print("\n".join(out))


def progressive_eta(task, past):
    """Remaining time of a task in progress, from what it has done so far.
    Without subagents: past tasks that reached the same number of model calls tell how much
    longer they went on (total / elapsed at that call). With subagents running: each one is
    estimated from its own assignment against past subagents, and the longest decides."""
    marks = task.get("call_marks") or []
    elapsed = task["dur_s"]
    sub = task.get("sub") or {}
    if sub.get("agents"):
        pool = [dict(a, key="%s%d" % (t["key"], i), agents=0, calls_by={}, cat=t.get("cat"))
                for t in past for i, a in enumerate((t.get("sub") or {}).get("agents") or [])
                if a.get("prompt") and a.get("dur_s", 0) > 5]
        if len(pool) >= 20:
            pred = Predictor(pool, {})
            med = pct([a["dur_s"] for a in pool], 0.5)
            left, lows, highs = [], [], []
            for a in sub["agents"]:
                sims = pred.similar(a["prompt"])
                durs = [x["dur_s"] for _, x in sims] or [a2["dur_s"] for a2 in pool]
                guess = weighted_median([(x["dur_s"], sc) for sc, x in sims]) if sims else med
                left.append(max(0.0, guess - a["dur_s"]))
                lows.append(max(0.0, pct(durs, 0.25) - a["dur_s"]))
                highs.append(max(0.0, pct(durs, 0.75) - a["dur_s"]))
            own = [t["dur_s"] - t["sub"]["busy_s"] for t in past if (t.get("sub") or {}).get("busy_s")]
            tail = pct([o for o in own if o > 0], 0.25) or 30
            return max(left) + tail, max(lows) + tail, max(highs) + tail
    k = min(len(marks) - 1, 20)
    if k < 1:
        return None, None, None
    ratios = [t["dur_s"] / t["call_marks"][k] for t in past
              if len(t.get("call_marks") or []) > k and t["call_marks"][k] > 0 and (t["agents"] > 0) == (task["agents"] > 0)]
    if len(ratios) < 20 or marks[k] <= 0:
        return None, None, None
    total = max(elapsed, marks[k] * pct(ratios, 0.5))
    low = max(elapsed, marks[k] * pct(ratios, 0.25))
    high = max(total, marks[k] * pct(ratios, 0.75))
    return total - elapsed, low - elapsed, high - elapsed


def cmd_eta():
    """Updated estimate for the task in progress, for an intermediate message."""
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID")
    paths = glob.glob(os.path.join(glob.escape(PROJECTS), "*", "%s.jsonl" % glob.escape(sid))) if sid else []
    if not paths:
        return
    tasks = parse_transcript(paths[0])
    if not tasks:
        return
    task = tasks[-1]
    idx = load_index()
    past = sorted((t for t in finished_tasks(idx) if is_work(t) and t["key"] != task["key"]),
                  key=lambda t: t["start_ts"])[-600:]
    left, low, high = progressive_eta(task, past)
    if left is None:
        print("⏱ Elapsed: %s" % fmt(task["dur_s"]))
    elif high - low < 10:
        print("⏱ Elapsed: %s · about %s left" % (fmt(task["dur_s"]), fmt(left)))
    else:
        print("⏱ Elapsed: %s · about %s left (likely %s)" % (fmt(task["dur_s"]), fmt(left), fmt_range(low, high)))


def cmd_estimate(args):
    combo = None
    if "--model" in args:
        i = args.index("--model")
        model = args.pop(i + 1)
        args.pop(i)
        effort = "high"
        if "--effort" in args:
            j = args.index("--effort")
            effort = args.pop(j + 1)
            args.pop(j)
        combo = (short_model(model), effort)
    idx, _ = update()
    block = estimate_block(" ".join(args), idx, combo, source="the command line")
    print(block or "Not enough history yet (fewer than 5 finished tasks with tool calls).")


def cmd_export_unlabeled(out_path):
    """Work tasks with no label yet, as JSONL for a classifier (the weekly job)."""
    idx, _ = update()
    labels = load_labels()
    tasks = idx["tasks"]
    rows = []
    for t in sorted(finished_tasks(idx), key=lambda t: t["start"]):
        if not is_work(t) or t["key"] in labels or t.get("category"):
            continue
        prev = tasks.get(t.get("prev_key") or "", {})
        rows.append({"key": t["key"], "prev": (prev.get("prompt") or "")[:150], "prompt": t["prompt"][:300],
                     "folder": t["cwd"], "tools": t.get("tool_names", {}), "edited": t.get("edit_exts", {})})
    with open(out_path, "w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")
    print("%d unlabeled tasks written to %s" % (len(rows), out_path))


def cmd_import_labels(paths):
    labels = load_labels()
    valid = set(CAT_CODES) | {"followup"}
    added = Counter()
    for path in paths:
        with open(path, encoding="utf-8") as fh:
            for key, cat in json.load(fh).items():
                cat = LEGACY_CATS.get(cat, cat)
                if cat in valid:
                    labels[key] = cat
                    added[cat] += 1
    write_json(LABELS, labels, indent=0, sort_keys=True)
    print("%d labels imported (%s), %d in total."
          % (sum(added.values()), ", ".join("%s %d" % kv for kv in added.most_common()), len(labels)))


def cmd_report():
    idx, _ = update()
    tasks = finished_tasks(idx)
    if not tasks:
        print("No tasks yet.")
        return
    resolve_categories(idx)
    lat = latency_table(tasks)
    work = [t for t in tasks if is_work(t)]
    durs = [t["dur_s"] for t in work]
    first = min(t["start"] for t in tasks)[:10]
    last = max(t["start"] for t in tasks)[:10]
    out = [
        "Tasks measured: %d (%s to %s): %d with tool calls, %d interrupted, "
        "%d monitoring (left out of the statistics)."
        % (len(tasks), first, last, len(work), sum(1 for t in tasks if t["interrupted"]),
           sum(1 for t in tasks if t.get("monitor"))),
        "",
        "Tasks with tool calls: median %s, p75 %s, p90 %s, max %s."
        % (fmt(pct(durs, 0.5)), fmt(pct(durs, 0.75)), fmt(pct(durs, 0.9)), fmt(max(durs) if durs else None)),
    ]
    plain = [t["dur_s"] for t in tasks if t["tools"] == 0 and not t["interrupted"]]
    if plain:
        out.append("Answers with no tool calls: median %s (n=%d)." % (fmt(pct(plain, 0.5)), len(plain)))
    out.append("")
    out.append("By category (real times, on the model used at the time):")
    for cat in CAT_CODES:
        group = [t for t in work if t["cat"] == cat]
        if not group:
            continue
        vals = [t["dur_s"] for t in group]
        models = Counter(t.get("model") or "?" for t in group).most_common(2)
        out.append("  %-10s n=%-4d median %-7s p75 %-7s p90 %-7s models: %s" % (
            cat, len(group), fmt(pct(vals, 0.5)), fmt(pct(vals, 0.75)), fmt(pct(vals, 0.9)),
            ", ".join("%s %d" % mc for mc in models)))
    out.append("")
    out.append("Model seconds per call (~ = extrapolated, never used):")
    for model in sorted({c.split("|")[0] for c in lat}, key=lambda m: -sum(n for c, (_, n) in lat.items() if c.startswith(m + "|"))):
        out.append("  %-12s %s" % (model, ladder(lat, model)))
    ranged = [t for t in tasks if t.get("est_range")]
    if ranged:
        inside = sum(1 for t in ranged if t["est_range"][0] <= t["dur_s"] <= t["est_range"][1])
        out.append("")
        out.append("Likely ranges given: %d, the real time fell inside %d times (%d%%, the target is 50%%)."
                   % (len(ranged), inside, round(100 * inside / len(ranged))))
    cal = calibration(tasks)
    out.append("")
    if cal:
        out.append("Estimates given: %d, median real/estimate %.1fx, %d%% within ±30%%."
                   % (cal["n"], cal["median"], round(cal["within"] * 100)))
        recent = sorted((t for t in tasks if t.get("estimate_min")), key=lambda t: t["start"])[-10:]
        for t in recent:
            out.append("  %s  est. %5s min  actual %7s  %-9s %-16s %s" % (
                t["start"][:16].replace("T", " "), "%g" % t["estimate_min"], fmt(t["dur_s"]),
                t["cat"], model_tag(t), shown_prompt(t, 40)))
    else:
        out.append("Estimates given: fewer than 3 so far, the estimate vs real comparison starts here.")
    out.append("")
    out.append("The 5 longest tasks:")
    for t in sorted(work, key=lambda t: -t["dur_s"])[:5]:
        out.append("  %7s  %s  %-9s %-16s %s" % (fmt(t["dur_s"]), t["start"][:10], t["cat"],
                                                 model_tag(t), shown_prompt(t, 50)))
    print("\n".join(out))


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    cmd = argv[1]
    if cmd == "hook-prompt":
        cmd_hook_prompt()
    elif cmd == "hook-stop":
        cmd_hook_stop()
    elif cmd == "hook-input":
        cmd_hook_input()
    elif cmd == "update":
        started = time.time()
        if "--file" in argv:
            idx, changed = update([argv[argv.index("--file") + 1]])
        else:
            idx, changed = update(force="--force" in argv)
        print("%d transcripts parsed, %d tasks in the index (%.1f s)."
              % (changed, len(idx["tasks"]), time.time() - started))
    elif cmd == "estimate":
        cmd_estimate(argv[2:])
    elif cmd == "eta":
        cmd_eta()
    elif cmd == "elapsed":
        cmd_elapsed()
    elif cmd == "status":
        cmd_status(argv[2:])
    elif cmd == "export-unlabeled":
        cmd_export_unlabeled(argv[2])
    elif cmd == "calibrate":
        idx = load_index() if "--no-update" in argv else update()[0]
        data = calibrate(idx)
        print(json.dumps(data, indent=1) if data else "Not enough tasks to calibrate.")
    elif cmd == "import-labels":
        cmd_import_labels(argv[2:])
    elif cmd == "report":
        cmd_report()
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
