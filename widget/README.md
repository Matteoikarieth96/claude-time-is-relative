# TaskETA widget

A small macOS 14+ menu bar app that shows each running Claude Code task as a bar: time so far, estimate and likely range. It reads only the small JSON files the task-eta hooks write in `~/.claude/task-eta/live/` and, to show session names, the titles in the Claude desktop app's session files. It has no network code and no sandbox entitlements, and it is signed ad hoc on your Mac when you build it.

Install it with `install.py` (it asks), or by hand:

```bash
./build.sh --run
```

`build.sh` compiles `Sources/*.swift` with `swiftc` from the Xcode Command Line Tools into `build/TaskETA.app`. Nothing is downloaded.

| File | What it holds |
|---|---|
| `Sources/TaskStore.swift` | reading the live files, state and colour of each task, time formats |
| `Sources/Views.swift` | bar, row, list and menu bar popover (SwiftUI) |
| `Sources/Panel.swift` | the optional desktop panel: desktop level, drag, saved position |
| `Sources/StatusItem.swift` | the menu bar item: a tick and the number of tasks done in the last 30 minutes |
| `Sources/Prefs.swift` | preferences and open at login (`SMAppService`) |
| `Sources/main.swift` | start-up, snapshots, demo data |

It reads Claude's ⏱ line from the transcript (`⏱ Estimated time with <model> <effort>: ~N min (likely X to Y min, <kind>)`, older lines too) and draws the range Claude declared. Before sharing your screen, turn on **Hide prompts and titles** in the menu: rows then show only the folder, and questions and job names are hidden.

For tests and screenshots: `TaskETA.app/Contents/MacOS/TaskETA --snapshot out.png [--dark] [--demo]` renders the panel to a PNG (`--demo` uses example tasks), `--selftest` checks the parsers of the files it reads (CI runs it), and `TASKETA_DEBUG_DIR=/some/folder` makes the running app write its state there four times a second.

To stop the live files without removing anything: `touch ~/.claude/task-eta/live.off`.
