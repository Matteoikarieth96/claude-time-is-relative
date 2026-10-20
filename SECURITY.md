# Security

## Threat model

task-eta runs on every prompt, as a Claude Code hook, with your user's permissions. It handles:

| Input | Risk |
|---|---|
| Claude Code transcripts (`~/.claude/projects/*/*.jsonl`) | They contain everything you and Claude wrote, including text pasted from the web. Personal data could leak if it were copied anywhere else; hostile text could try to steer Claude when it is shown back as a "similar past request" |
| The JSON Claude Code passes to the hooks on stdin | Malformed or unexpected input must never break a prompt or write outside the data folder |
| `~/.claude/settings.json` and `~/.claude/CLAUDE.md` | The installer edits files that control Claude Code; a bad edit could disable your other hooks or lose your settings |
| The widget's live files and the Claude desktop app's session files | Read by a long-running app; a path inside them must not make it open or run anything |

Assets protected: your transcripts and prompts (they never leave the machine), your Claude Code configuration, and the file system outside `~/.claude/task-eta`.

## Mitigations implemented

| Mitigation | Where |
|---|---|
| No network code: Python standard library only (no `urllib`, `socket`, `http`), the Swift app uses no networking API. Nothing is downloaded at install; the widget is compiled from the source in this repository | `task_eta.py`, `install.py`, `widget/Sources` |
| Nothing is installed without a yes: the first question is whether to install at all, and any question left unanswered (no terminal, no command-line answer) counts as no. Reading past sessions is a separate yes; with a no, tasks that started before the install are never indexed (`config.json` `since`) | `install.py` (`Ctx.ask`, `install`), `task_eta.py` (`history_since`) |
| Data minimisation: the index keeps the first 300 characters of each prompt, the first 400 of each subagent brief (written by Claude, used to estimate subagents), durations, model, effort, tool names and tool-use ids, file extensions, the name of the working folder, the transcript path and the session id. Claude's replies are not kept | `task_eta.py` (`finish`, `parse_subagent`) |
| Past prompts in any output (the hook's block, `report`, `status`): normalised (NFKC, so fullwidth look-alikes become plain characters), with control, format and surrogate characters (bidi overrides included), quotes and their look-alikes, square brackets and ⏱ ⏲ removed, so a snippet cannot pass for the block's own text; the block shows at most 5, cut to 70 characters; prompts of automated `claude -p` runs are never shown; the block and the CLAUDE.md rule say the quoted requests are data | `task_eta.py` (`short`, `shown_prompt`, `estimate_block`), `install.py` (`claude_md_block`) |
| Hostile transcript text cannot slow the hooks down: ⏱ lines are cut to 300 characters and parsed with patterns that have no adjacent open-ended repeats (a test times them on 5,000-character adversarial lines); estimates and ranges above a week are ignored; wrapped blocks (reminders) are removed in linear time even when their closing tag is missing; messages are looked at up to 200,000 characters; a lone surrogate (half an emoji) is replaced instead of breaking the index; lines nested too deep for the JSON parser are skipped instead of stopping the indexing; timestamps outside 2000 to 2100 are ignored | `task_eta.py` (`EST_RE`, `estimate_line`, `load_record`, `parse_ts`), `tests/test_hardening.py` |
| Only plain files are read: a transcript, subagent transcript, subagent `.meta.json`, live file or desktop-app session file that is a FIFO, a device or a folder is skipped, in the hooks and in the widget, so nothing can block on it. The calibration runs as its own background process, so the Stop hook stays quick on a long history | `task_eta.py` (`regular_file`), `widget/Sources/TaskStore.swift` (`isRegularFile`) |
| Session ids from hook input are reduced to ASCII `[A-Za-z0-9_.-]` before they become file names, so they cannot leave the live folder; the PostToolUse shell hook exits unless the id is made only of ASCII letters, digits, `_` and `-` (spelled out, not a locale-dependent range) | `task_eta.py` (`live_path`, `input_path`), `install.py` (`our_hooks`) |
| Live-file cleanup and `--purge` delete only files task-eta wrote, checked by their content, never by name alone, and never remove a folder chosen through `TASK_ETA_DIR` or `TASK_ETA_LIVE_DIR`, so pointing those at another folder cannot delete anything else. Empty values of these variables count as unset | `task_eta.py` (`live_prune`, `is_live_file`) |
| Hooks never fail a prompt: input that is not a JSON object counts as empty, errors go to `/dev/null`, every hook command ends with `\|\| true`, live-file errors are swallowed | `task_eta.py` (`read_hook_input`, `quietly`), `install.py` |
| Writes are atomic (temporary file, then rename) for the index, the calibration, the labels, live files, `settings.json` and `CLAUDE.md`. An index this version cannot read is moved aside, never overwritten | `task_eta.py` (`write_json`, `load_index`), `install.py` (`write_atomic`) |
| Installer: checks everything before writing anything (valid JSON, expected shapes, UTF-8, writable files and folders, one clean pair of CLAUDE.md markers) and stops with nothing changed otherwise; backs up every file under a name that is never reused; follows a `settings.json` or `CLAUDE.md` that is a link and changes its target instead of replacing the link; finds its own hooks only by a tag it writes (`# task-eta-hook`) or by the exact shape of older task-eta hooks, so no other hook is touched; never replaces a real `~/.claude/skills/task-eta` folder; shell-quotes every path in hook commands and in the rule | `install.py` |
| Installer and the widget app: an existing `~/Applications/TaskETA.app` is replaced or deleted only if it is a real folder (not a link) with this widget's bundle id; a read-only `CLAUDE.md` is left as it is on uninstall | `install.py` (`app_is_ours`, `purge`, `uninstall`) |
| Widget: every number read from a file is checked (finite, within a plausible range) before any conversion, so broken or hostile files cannot crash it; it reads Claude's ⏱ line at most 512 KB per refresh and stops 8 MB in; it shows the live folder in the Finder with `activateFileViewerSelecting`, never `open`, so a planted path cannot launch an app; text from files is rendered verbatim (`Text(String)`); it requests no entitlements and runs nothing | `widget/Sources/TaskStore.swift` (`sanitized`, `safeInt`, `declaredEstimate`), `widget/Sources/Prefs.swift` |
| Published files are checked by a test for email addresses, home-folder paths (also as Claude Code encodes them in folder names), session ids, secret-like strings, PNG text chunks and data files; `.gitignore` excludes data files, exports, widget debug output and Claude Code's per-project folder | `tests/test_no_private_data.py`, `.gitignore` |
| CI actions are pinned by commit SHA, run with read-only permissions and `persist-credentials: false` | `.github/workflows/ci.yml` |

Tests with hostile or broken input: `tests/test_hardening.py` (one test per finding of the pre-release review: slow-regex lines, absurd estimates, closing lines read as estimates, deep JSON nesting, FIFOs and devices as transcripts, foreign files in the live folder, an unreadable index, glob characters in the home path, snippets dressed as the block's text), `tests/test_install.py` (no yes means no change, invalid or oddly shaped `settings.json`, unbalanced CLAUDE.md markers, dotfiles links, backups never overwritten, other tools' hooks kept, `--purge` keeping foreign files, quoted paths), `tests/test_task_eta.py` (non-object hook input, a session id with `../`).

## Residual risks

- **Snippets of your past prompts reach the model.** Up to 5 short snippets per prompt, as part of your own conversation with Claude. If a past prompt contained pasted hostile text, a 70-character piece of it could appear again in the block. Claude is told they are past requests.
- **The index holds prompt snippets in plain text** in `~/.claude/task-eta/index.json`, readable by anything that runs as your user, like the transcripts it comes from. `install.py --uninstall --purge` deletes it.
- **The transcript format is not a public API.** A Claude Code update could make the parser miss tasks; it fails quietly (no estimate) rather than loudly.
- **The widget is signed ad hoc**, not notarized: it is built on your Mac from this source, so Gatekeeper does not quarantine it, but there is no Apple signature to check.
- **Hooks run with the Python that ran the installer.** If that Python is removed or replaced, the hooks stop (quietly) until you run `install.py` again.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting: the **Security** tab of this repository, then **Report a vulnerability**. Do not open a public issue for security problems. Include the input that triggers the problem and what you expected to happen.
