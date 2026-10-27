# Gaming Mode

Gaming Mode is a branch of task-eta that turns the TaskETA menu bar app into a game. It was built by
[@smazzolo](https://github.com/smazzolo) and contributed in
[pull request #3](https://github.com/Matteoikarieth96/claude-time-is-relative/pull/3); it lives on the
`gaming-mode` branch and is kept apart from `main`, which stays the plain version.

The estimates are task-eta's own: the engine in `task_eta.py` is the same, touched only to make it faster
and to add the game's lines. Gaming Mode adds a richer TaskETA app, two small games, an optional iPhone widget
and a few extra lines in the hooks. No account and no telemetry; what can leave your Mac is listed under
[Privacy](#privacy).

The app speaks English by default and Italian too (see [Language](#language)).

## What it adds

**Menu bar and list**
- A coloured box in the menu bar: prompts running, done in the last hour, and the time of the longest one
  (`▶ 3  ✓ 2  ⏱ 12m04s`). Green on time, orange past the estimate, red past the range, a hand when Claude needs you.
- The list opens when the pointer rests on the icon and closes when it leaves; a double click opens the dashboard.
- One row per session, earlier requests folded under it. The overrun is written out ("+10 min over the
  estimate (×6)") and the bar past the estimate is striped. A click on the title opens that chat in the Claude app.

**Desktop panel**
- The same list in a glass panel on the desktop that scrolls (Liquid Glass on macOS 26, the older blur before),
  and a short version with only the counts that blinks green when a task finishes and orange when Claude needs you.

**End of a task**
- A few seconds of animation in the row, one per outcome: fireworks on the estimate, a rocket under the range,
  confetti within it, flames past it ("This is fine"). The menu bar box shows the outcome too. Only the sticker
  with Reduce Motion.

**Dashboard** (double click, or ⌘D)
- A grid of widgets you can move, resize, add and remove: tasks and hours, how often the estimates were right,
  estimate against real time, where the estimates miss (by kind, model and project), hours per day, a heat map
  of days and hours, the history with a link to each chat, "useless stats" such as "Doomscrolling avoided".
- An optional weekly analysis (see [`widget/insights`](widget/insights/README.md)).

**Notifications**
- The app's own glass toasts when a task finishes or Claude needs you, with the widget in view, always or
  never. One per session, a ✕ to close it. macOS notifications are used when you allow them.

**Touch Bar** (Macs that have one)
- A Control Strip button with the most urgent session, and a full bar with one button per session. Off by
  default: turn it on in Settings. It uses private macOS calls (DFRFoundation), so a macOS update can break it.

**The Mine** (the estimates game, Minecraft style)
- Every task with Claude's estimate is a pickaxe stroke, and what you find says how good the estimate was:
  Diamond (within 5%), Emerald, Gold Ingot, Iron Ingot, Coal, then Cobweb down to Rotten Flesh.
- 9 diamonds make a Block of Diamond; a week with 80% good finds and at least 20 strokes lights a Beacon.
  The pickaxe is the level (wood to diamond), and Claude rates its own estimates at the end of each reply.
- No Minecraft artwork ships with the app: each find is drawn as a coloured square. If you own icons you are
  allowed to use, a PNG per find in `~/.claude/task-eta/minerali` replaces the square (the Mine card lists the file
  names it looks for).

**Mini golf** (an easter egg)
- Click the "running" dot 101 times, or drag it holding ⌘ M G, and the list becomes a mini golf course:
  slingshot shots, cushions, par and streaks, a round of 18 holes a day with obstacles, a different twist every
  day (wind, portals, a shy hole…), achievements, and a heat map of your shots. The cheer when you sink the ball
  uses the Mac's voices, or a clip of yours named `cheer` in `~/.claude/task-eta/sounds`.

**The Course** (the level game, in the dashboard)
- A 9-hole map where each hole is a level with its trials and a power to unlock.

**iPhone widget** (optional, off by default)
- A [Scriptable](https://scriptable.app) widget that shows your sessions on the Home and Lock Screen, served by
  the app on your local network (see [Privacy](#privacy)).

**Hooks**
- The `elapsed` line ends with what the estimate found in the mine ("· Emerald") and says when the next pickaxe
  is ready; `task_eta.py piccone` (or `pickaxe`) shows it, and `piccone su` takes it only when you ask.
- The `[task-eta]` block gets one line with Claude's own score, measured against the range the hook offered,
  never the range Claude wrote. `task_eta.py score off` and `TASK_ETA_MINE=off` turn the game lines off.
- `task_eta.py language` shows or sets the language (below).

## Privacy

Everything in `main`'s [privacy table](README.md#privacy) still holds for the hooks: Python standard library
only, no network code, files private to your user. Gaming Mode adds:

| | |
|---|---|
| **Writes** | In `~/.claude/task-eta/`: `miniera.json` (the mine's pickaxe), `language.json`, the weekly analysis' `insights-input.json` and `insights.json` if you set it up. Folders you fill yourself: `logos/`, `minerali/`, `sounds/`. |
| **Network** | Only the iPhone widget, off until you turn it on. Then the app answers on port 8765 of your local network, over plain HTTP, and only to requests that carry its random code. The code sits in the script the app writes to iCloud Drive > Scriptable, so it syncs through your iCloud account. Only devices on the subnet of the Mac's Wi-Fi or Ethernet get an answer (a /16 or narrower; VPN tunnels never). By default the iPhone gets only each task's folder name; with "Prompts and titles on the iPhone" on, prompts and session titles cross your network unencrypted, so keep that off on networks you don't trust. Turning the widget off deletes the script from iCloud Drive. |
| **Claude** | The weekly analysis, if you schedule it, hands Claude a file of numbers and labels (project and model names, kinds of work): no prompts, paths or session ids. Like any conversation, that file reaches the model. |
| **Never** | No telemetry, no account, nothing sent to the authors. |

`python3 install.py --uninstall --purge` removes the history and the files above that the app wrote; the
folders you filled yourself are left alone.

## Language

English is the base language; Italian is the second. Pick **Language / Lingua** at the top of Settings
(⌘,): System, English or Italiano. It applies at once, no relaunch. System follows the Mac's first language and
falls back to English.

The choice is saved in `~/.claude/task-eta/language.json`, shared by the app and the hooks, so the end of the
`elapsed` line follows it too. From a terminal:

```bash
python3 task_eta.py language it
```

`it` can be `en` or `system` too. The lines the hooks write for Claude stay in English. Every text in the app is
`L("English", "Italiano")` (`widget/Sources/Loc.swift`); the English side keeps its template (`"{1} running"`),
so a third language can be added as a lookup keyed by the English text (the file explains how).

## Build and install

Needs macOS 14+, Python 3.9+ and the Xcode Command Line Tools (`xcode-select --install`). Check out this branch,
then install task-eta as in the [README](README.md) (`python3 install.py`), saying yes to the widget, or build
the app by hand:

```bash
./widget/build.sh
```

```bash
./widget/build/TaskETA.app/Contents/MacOS/TaskETA --selftest
```

```bash
python3 -m unittest discover -s tests
```

Then quit a running TaskETA, copy `widget/build/TaskETA.app` to `~/Applications` and open it. To preview without
installing, `TaskETA --snapshot out.png --demo` draws the panel and `--dashboard-snapshot out.png` the dashboard;
`TASKETA_LANG=it` or `TASKETA_LANG=en` draws them in that language.

## Credits and licence

- Gaming Mode: [@smazzolo](https://github.com/smazzolo), MIT like the rest of the repository.
- Fonts: Barlow (`widget/campo/fonts`), Pixelify Sans and VT323 (`widget/miniera/fonts`), each under the SIL Open
  Font License 1.1, whose text ships next to the files.
- Minecraft is a trademark of Mojang Synergies AB. Gaming Mode is not affiliated with or endorsed by Mojang or
  Microsoft, and ships none of their artwork or sounds.
