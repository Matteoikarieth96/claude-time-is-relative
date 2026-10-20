# Claude Time is relative (to you)

Time estimates for Claude Code, learned from your own past sessions, on your own machine.

> Not affiliated with Anthropic. "Claude" and "Claude Code" are Anthropic's names for its products; this is an independent open-source tool for them.

## The problem

You ask Claude Code for something. How long will it take? Claude does not know. A model has no clock and no memory of its past work, so it guesses. In 96 test tasks on the author's Mac, Claude's own guesses were about 3 times too long, and only 16% landed within 2x of the real time.

## The solution

Claude Code already keeps a transcript of every session on your computer. task-eta reads them, measures how long each of your tasks really took, and before each new task gives Claude an estimate built from that history, re-timed for the model and effort you are using. When the task is done, Claude prints the real time next to it.

```
⏱ Estimated time with opus-5-5 high: ~4 min (likely 2 to 9 min)
  … Claude works …
⏱ Actual time: 5 min (likely 2 to 9 min: inside)
```

Nothing leaves your machine. The estimates are relative to you: your tasks, your models, your pace.

![How it works: measure, sort, re-time, estimate, check](docs/how-it-works.png)

## Install

Needs Claude Code (CLI or desktop app), Python 3.9 or newer, macOS or Linux. The optional widget needs macOS 14+ and the Xcode Command Line Tools.

```bash
git clone https://github.com/Matteoikarieth96/claude-time-is-relative.git
```

```bash
python3 claude-time-is-relative/install.py
```

The installer first says what it reads and writes, then asks before it changes anything:

1. **Install?** Two hooks in `~/.claude/settings.json` and the skill link. No: nothing changes.
2. **Read your past sessions now?** Yes: the estimates use your own times from the first prompt. No: it starts from today and never reads older sessions.
3. **Add a short rule to `~/.claude/CLAUDE.md`?** It makes Claude follow the format more reliably. The hook works without it.
4. **Install the TaskETA menu bar widget?** (macOS only) It is built on your Mac from the source in `widget/`, then copied to `~/Applications`. If yes: **open it at login?** Off unless you say so.

A question left unanswered counts as no. It backs up every file before changing it (`settings.json.task-eta-backup-…`), follows a `settings.json` or `CLAUDE.md` that is a link to your dotfiles instead of replacing it, stops with nothing changed if a file is not what it expects (not valid JSON, read-only, odd markers), and never touches a hook that is not its own. Use `--dry-run` to see the changes first, or `--check` to see what is installed.

You can also ask Claude: *"set up task-eta from this folder"*. The skill explains the same things and asks the same questions before it runs the installer.

## Privacy

![Privacy: what it reads, what it writes, what it never does](docs/privacy.png)

| | |
|---|---|
| **Reads** | The transcripts Claude Code already keeps in `~/.claude/projects`, only after you say yes. On a Mac with the Claude desktop app, the model, effort and title of each session from the app's own files. |
| **Writes** | `~/.claude/task-eta/`: your task times, the first 300 characters of each prompt, model and effort. The hooks in `~/.claude/settings.json`, the optional rule in `~/.claude/CLAUDE.md`, the optional app in `~/Applications`. |
| **Never** | No network code (Python standard library only, a Swift app with no networking), no telemetry, no account. The author receives nothing. |
| **Good to know** | To help Claude, the hook adds up to 5 snippets (70 characters each) of your own similar past prompts to each new prompt. They reach the model like the rest of your conversation. |

Remove everything with `python3 install.py --uninstall`; add `--purge` to delete your history too.

## What you see

![The estimate line, the actual time line and the widget bar](docs/the-line.png)

- **Before**: `⏱ Estimated time with <model> <effort>: ~N min (likely X to Y min)`. The range is built to hold the real time about one time in two.
- **After**: `⏱ Actual time: N min (likely X to Y min: inside)`.
- **During a long task**: Claude may add `⏱ Elapsed: 12 min · about 8 min left (likely 5 to 15 min)`, re-estimated from the work done so far.
- **With subagents**: the line ends with `, with subagents`, and the estimate comes from your past tasks that used them.

### The widget

TaskETA lives in the menu bar: a tick and the number of tasks finished in the last 30 minutes. Click it for every running task as a bar, with the time so far, the estimate and the likely range. Tasks waiting for your answer come first. An optional panel can sit on the desktop, under your windows (off until you turn it on in the menu).

| Light | Dark |
|---|---|
| ![TaskETA, light](docs/widget-light.png) | ![TaskETA, dark](docs/widget-dark.png) |

Example data. Green: on time. Yellow: past the estimate. Red: past the likely range. Grey: quiet for 15 minutes.

## How accurate is it

![Claude guessing vs task-eta](docs/problem.png)

Measured on the author's history (1,314 tasks with tool calls, July to October 2026), each task estimated only from the tasks before it, as the hook would have done at the time:

| | Within 2x of the real time | Median error | Real time inside the likely range |
|---|---|---|---|
| Claude guessing, test tasks (96) | 16% | about 3x too long | n/a |
| task-eta, test tasks (582) | 77% | 35% | 49% |
| task-eta, real day-to-day tasks (328) | 38% | 77% | 44% |
| task-eta, tasks with subagents (73) | 23% | 115% | 26% |
| mid-task `eta`, after 20 model calls (45) | | 17% | |

Real work varies far more than test tasks, and the first estimate is the hardest one: treat it as a calibrated guess, not a promise. It improves as the history grows and narrows once the task is under way. Run `python3 task_eta.py report` to see your own numbers.

## Commands

```bash
python3 task_eta.py report          # your task times by kind, model seconds per call, estimate accuracy
python3 task_eta.py estimate "write a deck about our Q3 results"
python3 task_eta.py estimate --model sonnet-5-5 --effort medium "fix the login bug"
python3 task_eta.py status          # running and recently finished tasks
python3 install.py --check          # what is installed
python3 install.py --uninstall      # remove it all (add --purge to delete the history)
```

## How a task is measured

- A task is one prompt you typed plus all the work it caused, background agents included, until the last action before your next prompt.
- Not counted: time waiting for your answers, silences over 15 minutes with no subagent running, pauses over an hour.
- A session started by another session is its own task. Notifications from CI or other sessions do not stretch the task that receives them.
- Tasks where Claude only kept waking up to watch something (a long build, a print) stay in the history but out of the statistics.
- Every model call is timed per model and effort, so a past task can be replayed as if it had run on another model or effort: only the model time changes, tool time stays as it was.

## Limits

- It needs history. Estimates start after 5 tasks that used tools and get better over the first few hundred.
- Claude Code deletes transcripts after 30 days by default (`cleanupPeriodDays`), so a first install starts with at most a month of history. From then on the index keeps every task it has read.
- The kind of a task comes from keyword rules in English and Italian. Add words of your language to `CAT_WORDS` in `task_eta.py`.
- The transcript format is not a public API. A Claude Code update could change it; the tests cover the parser on synthetic transcripts.
- Hooks use `sh`, so Windows is not supported.

## Files

| File | What it is |
|---|---|
| `task_eta.py` | the whole tool: parser, index, estimates, hooks, commands |
| `install.py` | install, check and uninstall, with backups |
| `SKILL.md` | the Claude Code skill: setup questions, reports, estimates on request |
| `widget/` | the TaskETA menu bar app (SwiftUI) and its build script |
| `docs/` | the images in this README; `docs/src/` has their source |
| `tests/` | unit tests on synthetic transcripts, plus a check that no personal data is published |

Run the tests with `python3 -m unittest discover -s tests`.

## More skills by the same author

[evm-dd](https://github.com/Matteoikarieth96/evm-dd-skill) · [hiring-prep](https://github.com/Matteoikarieth96/hiring-prep-skill) · [whiteboard-video](https://github.com/Matteoikarieth96/whiteboard-video-skill) · [beer-can-label](https://github.com/Matteoikarieth96/beer-can-label-skill) · [3d-print-design](https://github.com/Matteoikarieth96/3d-print-design-skill)

## License

MIT, see [LICENSE](LICENSE).
