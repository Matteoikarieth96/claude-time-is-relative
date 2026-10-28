---
name: task-eta
description: Time estimates for Claude Code tasks, learned from the user's own past sessions on this machine ("Claude Time is relative (to you)"). Use when the user asks how long a task will take or took, wants a report of their task times, asks how accurate past estimates were, wants the timing history rebuilt, or wants to install, set up, check or remove task-eta or its TaskETA menu bar widget. The ⏱ line at the start of each task comes from the hooks, not from this skill.
---

# task-eta

Measures how long Claude Code tasks take on this machine and uses that history to estimate new ones. Everything stays on this machine: `task_eta.py` and `install.py` use the Python standard library only and have no network code.

`SKILL_DIR` below is the folder of this file. Paths may contain spaces: always quote them.

## Setup (first use)

Run `python3 "$SKILL_DIR/install.py" --check`. If the hooks are missing, offer the setup before anything else:

1. Tell the user in a few plain lines what it does, before asking anything:
   - it reads the transcripts Claude Code already keeps in `~/.claude/projects` and writes its own history to `~/.claude/task-eta/` (task times, the first 300 characters of each prompt with API keys and other secrets masked, model, effort), private to the user;
   - nothing is sent anywhere, there is no account and no telemetry, the author receives nothing;
   - the hook lists the user's similar past requests of the same project by kind, time and tool calls only, never their text;
   - every changed file is backed up in `~/.claude/task-eta/backups`, and `install.py --uninstall` undoes it all (`--purge` also deletes the history).
2. Ask with AskUserQuestion, one call, four questions:
   - **Install**: add the two hooks (`UserPromptSubmit`, `Stop`) to `~/.claude/settings.json` and link the skill? (If `--check` shows task-eta hooks from an older setup, say they will be replaced; if `~/.claude/skills/task-eta` links to another copy of task-eta, say it will point here until uninstall.) If the answer is no, stop here and change nothing.
   - **History**: read your past sessions now, so estimates use your own times (recommended), or start from today?
   - **Rule**: add a short rule to `~/.claude/CLAUDE.md` so Claude follows the format more reliably (recommended), or rely on the hook alone?
   - **Widget** (macOS 14+ only; elsewhere leave it out): no widget, the TaskETA menu bar app, or the app and open it at login? It is built here from source and needs the Xcode Command Line Tools. With the widget, four more hooks go into `~/.claude/settings.json` (`PreToolUse`, `PermissionRequest`, `Notification`, `PostToolUse`): they tell it when a session waits for the user.
3. Run the installer with the answers, never with answers the user did not give:
   `python3 "$SKILL_DIR/install.py" --hooks yes --history yes|no --claude-md yes|no --widget yes|no --login yes|no`
   Add `--dry-run` first if the user wants to see the changes. Report what it printed in a few lines: how many past tasks it found, which files changed and where the backups are. If it says "Nothing changed", tell the user why in its words and do not work around it.
4. New prompts get the estimate from the next one on. With fewer than 5 past tasks that used tools, there is no estimate yet.

## Commands

```bash
S="$SKILL_DIR/task_eta.py"
python3 "$S" report            # summary: by kind of work with out-of-sample accuracy, estimates, longest tasks, errors
python3 "$S" estimate "TEXT"   # the same block the hook adds, for any task description
python3 "$S" estimate --model sonnet-5-5 --effort medium "TEXT"   # re-timed for another model and effort
python3 "$S" elapsed           # real time of the task in progress (last line of the reply)
python3 "$S" eta               # remaining time of the task in progress (intermediate updates)
python3 "$S" status [--json]   # tasks in progress and the last finished ones (widget data)
python3 "$S" calibrate         # re-measure each kind's range and accuracy (the Stop hook does it on its own)
python3 "$S" import-sleeps     # leave out the Mac's sleeps logged by macOS (about a week back), then re-parse
python3 "$S" update [--force]  # read new or changed transcripts; --force re-reads all of them
```

## Answering the user

- "How long will X take": run `estimate` with the user's words (add `--model` and `--effort` if they name one). Decide which kind of work it needs (quick: 1-3 tool calls, medium: 4-15, long: 16+, with brief subagents, with subagents; a file of 150+ lines counts as 3 calls), give that kind's line, and say which kind and why. Its similar past requests show kind, time and tool calls only, never the prompts.
- Say when a number is extrapolated (the block says "its speed is extrapolated", `report` marks it with `~`): that model and effort was never used here.
- "How long did it take" or a report: run `report` from the project's folder and summarize it in a few lines. It quotes prompts of that project only. Do not paste the raw output, and do not quote the user's past prompts back beyond what they need.
- Times are wall clock until done, background agents included, time waiting for the user excluded, in seconds under 90 s and otherwise in minutes. Say so if the user compares them with their own clock.

## How it works

- `task_eta.py` splits each transcript into tasks: one prompt the user typed plus all the work it caused. Duration runs from the prompt to the last activity, minus waits for the user (AskUserQuestion answers, silences over 15 minutes inside a turn with no subagent running, pauses over 1 hour between turns unless an Agent or Workflow of the task ran through them). A turn also ends with the desktop app's `wrap_up` tool. A session started by another session is its own task. Tasks where Claude only kept waking up to watch something are left out of the statistics; so are automated `claude -p` runs.
- Background Agent and Workflow runs belong to the task that launched them: when one reports back after the user moved on, that task is extended to the report (at most to the end of its agents' transcripts plus 2 minutes, or 1 hour) and the later task is not charged. A task whose agent has not reported yet is left out of the statistics for 12 hours.
- Kind of work, from the transcript: quick (1-3 tool calls), medium (4-15), long (16+), agents (any Agent, Task or Workflow call), text (no tools: no line). A Write or Edit of 6000+ new characters (about 150 lines) counts as 3 calls. The estimate protocol's own `elapsed`/`eta` calls and the app's bookkeeping calls (`update_plan`, `wrap_up`, `mark_chapter`, ToolSearch, Skill, the terminal's task list) do not count, as the block tells Claude. Tasks with subagents get two lines: "with brief subagents" (every subagent under 10 minutes) and "with subagents"; both are the kind agents.
- Time the Mac was asleep between Claude's steps is left out: the hooks record the kernel's last sleep and wake (`sleeps.json`), and after a new wake the Stop hook reads macOS's power log in the background (at most once an hour), since the kernel only tells the last stretch; `import-sleeps` does it at once and re-parses. Sleep inside one model call, a subagent's run or a background job still counts.
- Each model call is timed per model and effort. A past task is re-timed for another model and effort by scaling only its model time; tool time stays as it was.
- The hook gives one line per kind: that kind's median duration, re-timed for the current model and effort, with the kind's measured spread as the likely range (for each kind, the narrowest of four quantile pairs whose range, as printed, held the real time (as the Actual line prints it: to the second under 90 s, whole minutes above, since 2026-10-28) at least 70% of the time on the tasks tested so far; the widest if none did; the quartiles under 20 tested tasks). Next to each line the block prints how often that range held on tasks it had not seen, if the kind is right (each task scored with the width picked before it), with "under the 70% target" when it fell short; a separate line gives the record of the lines as printed (the last 100, overall and by the kind declared, with the shares that finished earlier and later). Since 2026-10-25 the range is wider (about 4-5x for medium and long) because it aims for 7 times in 10, not 1 in 2. When the session's model is not known yet (first prompt of a terminal or headless session), every model family with measured speeds gets its lines. Claude copies the line of the kind it plans. Topic categories (coding, research…) and similar requests do not change the number; the similar requests (same project only) are listed to help pick the kind.
- `calibrate` scores each kind out of sample on the user's last 300 tasks (each predicted only from tasks that had ended before it), and how often the kind Claude declared was the real one. Tasks hit by API or network errors (the Mac asleep, no network, overload) or by a context compaction count too, since the printed lines meet them, and the closing `Actual time` line names them. The Stop hook reruns it in the background when 5+ tasks were added or after 6 hours.
- `eta` reads the task list Claude keeps (the app's `update_plan`, the terminal's `TaskCreate`/`TaskUpdate`): with 3+ steps and at least one done, the time left is the time per step done so far, times the steps left, times how far that pace was off on the user's past lists (82-240 past points: the miss on the time left fell from about 2.7x to 2.0x). Without a list it uses the call count as before.
- The author's experiment since 2026-10-25, off unless turned on (`TASK_ETA_CALLS_LINE=1` in the hooks' environment, for example through the `env` setting of `~/.claude/settings.json`): the block asks Claude to write the tool calls it plans after the ⏱ line, as an empty line and then the Markdown link definition `[//]: # (task-eta: ~N call, A agents, L long)`, which the app does not show: N tool calls, A subagents, L of them expected to run 10+ minutes (since 2026-10-28; the older `[//]: # (task-eta: ~N call)` is still read). The parser reads these whenever a reply has them and stores them as `calls_declared`, `agents_declared` and `long_declared`; nothing uses them yet.
- Secrets in prompts (API keys by prefix, PEM blocks, JWTs, keys in URLs, passwords, long letter-digit strings) become `[secret]` in everything stored or shown. Model and effort names are checked against a whitelist before they are stored or shown.
- The index (`~/.claude/task-eta/index.json`) is written under a lock, with a daily copy (`index.json.bak`); one that cannot be read is moved aside (`index.json.unreadable-<time>`), never overwritten, and the daily copy stands in. Failed runs append a traceback to `errors.log`: the hooks hide stderr. All files are private to the user (0600, folders 0700).
- Hooks: `UserPromptSubmit` runs `hook-prompt` (adds the `[task-eta]` block), `Stop` runs `hook-stop` (updates the index and the calibration). With the widget, `PreToolUse`, `PermissionRequest`, `Notification` and `PostToolUse` mark when a session is waiting for the user.
- On macOS with the Claude desktop app, the current model and effort come from the app's session file (`~/Library/Application Support/Claude/claude-code-sessions/`), read only. Elsewhere, from the session's last reply.

## When something looks wrong

- No `[task-eta]` block in the prompt: look at `~/.claude/task-eta/errors.log`, run `install.py --check`, then pipe-test the hook: `echo '{"prompt":"test"}' | python3 "$S" hook-prompt`.
- An `index.json.unreadable-…` file: the index could not be read and was set aside; the daily copy took its place. Check the aside file before deleting it.
- A duration looks absurd: ask the user which task, then look at its numbers (`segments`, `active_s`, `wait_s`, `bg_tail_s`, `pending_bg`, `monitor`) in `~/.claude/task-eta/index.json` with a command that prints only that task, such as `python3 -c` with `json`. Do not read the whole file: it holds prompt snippets from every project.
