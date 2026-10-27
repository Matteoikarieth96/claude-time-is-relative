# TaskETA widget

A small macOS 14+ menu bar app that shows each running Claude Code task as a bar: time so far, estimate and likely range. It reads only the small JSON files the task-eta hooks write in `~/.claude/task-eta/live/` and, to show session names, the titles in the Claude desktop app's session files. It has no sandbox entitlements and is signed ad hoc on your Mac when you build it. Its only network code is the optional iPhone widget server (Settings > iPhone, off by default): it answers `GET /status` on port 8765, only to devices on the subnet of the Mac's Wi-Fi or Ethernet (a /16 or narrower) and only with the code; prompts and session titles go to the iPhone only if you turn that on, for the Scriptable widget in `iphone/TaskETA.js`.

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
| `Sources/StatusItem.swift` | the menu bar item: a coloured box with prompts running, prompts finished and the time of the longest running one (a hand first when a task waits for you); the list opens on click or when the pointer rests on it |
| `Sources/Prefs.swift` | preferences and open at login (`SMAppService`) |
| `Sources/Notifier.swift` | announcements when a task finishes or waits for you (with the widget in view, always or never): macOS notifications when allowed, else the app's own, since macOS refuses them to an app signed ad hoc; the link to a session's chat (`claude://code/continue?session=local_…`) |
| `Sources/Dashboard.swift` | the dashboard window (history from task-eta's index, Swift Charts) and the settings window |
| `Sources/Golf.swift` | the mini golf hidden behind the "running" dot (slingshot, bounces, hole), unlocked at its 101st click |
| `Sources/Gems.swift` | the estimates as a round of golf: gems, points, levels, rounds, challenge, and what they are for (dashboard) |
| `Sources/GolfStats.swift` | the mini golf's history and game layer: par, points, streaks, challenge of the day, achievements |
| `Sources/DotFeedback.swift` | the "running" dot: every press counted, its jolt, count and sound, the drag with ⌘ M G held that unlocks the mini golf |
| `Sources/Celebration.swift` | the few seconds of animation on a row that has just finished, one per outcome: fireworks on the estimate, a rocket under the range, confetti within it, flames past it |
| `Sources/DashboardGrid.swift` | the dashboard as a grid of widgets: sizes, edit mode, the saved layout, the shared look of a widget |
| `Sources/FunStats.swift` | "Useless stats", worked out from the index and shown only on this Mac |
| `Sources/Marks.swift` | the projects' coloured initials and logos, the models' glyphs |
| `Sources/Insights.swift` | the week's analysis written by an outside scheduled task (`insights/`), as a dashboard widget |
| `Sources/Hover.swift` | hover to click on safe actions |
| `Sources/TouchBar.swift` | the Control Strip button and the full Touch Bar with the sessions (private DFRFoundation calls) |
| `Sources/PhoneServer.swift` | the optional local server for the iPhone widget (`iphone/TaskETA.js`) and the script kept in iCloud Drive |
| `Sources/Campo.swift`, `CampoEngine.swift`, `CampoStyle.swift` | «Il campo» (The Course), the game of levels: rules, engine, the map (`campo/`) in a web view, its look |
| `Sources/GolfRules.swift`, `GameMood.swift` | the mini golf's courses and the strong club; the game's mood (The Mine or Mini golf); `Miniera.swift`, `Drops.swift`: The Mine, the Minecraft-style estimates game |
| `Sources/Loc.swift` | the language: `L("English", "Italiano")` for every text, the choice (System, English, Italiano) shared with the hooks in `~/.claude/task-eta/language.json`, live switching |
| `Sources/main.swift` | start-up, snapshots, demo data, the selftest |

It reads Claude's ⏱ line from the transcript (`⏱ Estimated time with <model> <effort>: ~N min (likely X to Y min, <kind>)`, older lines too) and draws the range Claude declared. Before sharing your screen, turn on **Hide prompts and titles** in the menu: rows then show only the folder, and questions and job names are hidden.

For tests and screenshots: `TaskETA.app/Contents/MacOS/TaskETA --snapshot out.png [--dark] [--demo | --celebrate]` renders the panel to a PNG (`--demo` uses example tasks, `--celebrate` four finished ones caught in their animations), `--selftest` checks the parsers of the files it reads (CI runs it), and `TASKETA_DEBUG_DIR=/some/folder` makes the running app write its state there four times a second.

To stop the live files without removing anything: `touch ~/.claude/task-eta/live.off`.
