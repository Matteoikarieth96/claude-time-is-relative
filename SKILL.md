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
   - it reads the transcripts Claude Code already keeps in `~/.claude/projects` and writes its own history to `~/.claude/task-eta/` (task times, the first 300 characters of each prompt, model, effort);
   - nothing is sent anywhere, there is no account and no telemetry, the author receives nothing;
   - the hook adds up to 5 snippets (70 characters) of the user's similar past prompts to each new prompt, so they reach the model like the rest of the conversation;
   - every changed file is backed up, and `install.py --uninstall` undoes it all (`--purge` also deletes the history).
2. Ask with AskUserQuestion, one call, four questions:
   - **Install**: add the two hooks to `~/.claude/settings.json` and link the skill? (If `--check` shows task-eta hooks from an older setup, say they will be replaced.) If the answer is no, stop here and change nothing.
   - **History**: read your past sessions now, so estimates use your own times (recommended), or start from today?
   - **Rule**: add a short rule to `~/.claude/CLAUDE.md` so Claude follows the format more reliably (recommended), or rely on the hook alone?
   - **Widget** (macOS 14+ only; elsewhere leave it out): no widget, the TaskETA menu bar app, or the app and open it at login? It is built here from source and needs the Xcode Command Line Tools.
3. Run the installer with the answers, never with answers the user did not give:
   `python3 "$SKILL_DIR/install.py" --hooks yes --history yes|no --claude-md yes|no --widget yes|no --login yes|no`
   Add `--dry-run` first if the user wants to see the changes. Report what it printed in a few lines: how many past tasks it found, which files changed and where the backups are. If it says "Nothing changed", tell the user why in its words and do not work around it.
4. New prompts get the estimate from the next one on. With fewer than 5 past tasks that used tools, there is no estimate yet.

## Commands

```bash
S="$SKILL_DIR/task_eta.py"
python3 "$S" report            # summary: percentiles, by kind of task, estimate accuracy, longest tasks
python3 "$S" estimate "TEXT"   # the same block the hook adds, for any task description
python3 "$S" estimate --model sonnet-5-5 --effort medium "TEXT"   # re-timed for another model and effort
python3 "$S" elapsed           # real time of the task in progress (last line of the reply)
python3 "$S" eta               # remaining time of the task in progress (intermediate updates)
python3 "$S" status [--json]   # tasks in progress and the last finished ones (widget data)
python3 "$S" calibrate         # re-measure the correction factor (the Stop hook does it on its own)
python3 "$S" update [--force]  # read new or changed transcripts; --force re-reads all of them
```

## Answering the user

- "How long will X take": run `estimate` with the user's words (add `--model` and `--effort` if they name one). Give one number per model and effort asked, the likely range, and the 2 or 3 most similar past tasks with their real times.
- Say when a number is extrapolated (`~` in the seconds-per-call ladder): that model and effort was never used here.
- "How long did it take" or a report: run `report` and summarize it in a few lines. Do not paste the raw output, and do not quote the user's past prompts back beyond what they need.
- Times are wall clock until done, background agents included, time waiting for the user excluded. Say so if the user compares them with their own clock.

## How it works

- `task_eta.py` splits each transcript into tasks: one prompt the user typed plus all the work it caused, including turns woken up by background agents. Duration runs from the prompt to the last activity, minus waits for the user (AskUserQuestion answers, silences over 15 minutes with no subagent running, pauses over 1 hour between turns). A session started by another session is its own task. Tasks where Claude only kept waking up to watch something are left out of the statistics.
- Each task gets a kind (coding, research, documents, social, design, video, hardware, setup, other) from keyword rules (English and Italian) and the files and tools it used.
- Each model call is timed per model and effort. A past task is re-timed for another model and effort by scaling only its model time; tool time stays as it was.
- The suggested estimate is the median of the kind of task, pulled toward the most similar past requests, re-timed, times a correction factor measured on the last 300 tasks (`calibrate`). The likely range is the middle half of past real/predicted ratios, so it holds the real time about one time in two.
- Hooks: `UserPromptSubmit` runs `hook-prompt` (adds the `[task-eta]` block), `Stop` runs `hook-stop` (updates the index and the calibration). With the widget, `PreToolUse`, `PermissionRequest`, `Notification` and `PostToolUse` mark when a session is waiting for the user.
- On macOS with the Claude desktop app, the current model and effort come from the app's session file (`~/Library/Application Support/Claude/claude-code-sessions/`), read only. Elsewhere, from the session's last reply.

## When something looks wrong

- No `[task-eta]` block in the prompt: run `install.py --check`, then pipe-test the hook: `echo '{"prompt":"test"}' | python3 "$S" hook-prompt`.
- A duration looks absurd: find the task in `~/.claude/task-eta/index.json` by its prompt and look at `segments`, `active_s`, `wait_s` and `monitor`.
