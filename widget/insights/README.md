# Weekly analysis (optional)

Once a week a scheduled Claude task acts as an outside analyst: it has no context about your projects or chats
and reads only numbers. Nothing here runs unless you create the task yourself.

1. `export.py` reads task-eta's index and writes `~/.claude/task-eta/insights-input.json`: numbers and labels only
   (project names, model names, kinds of work), with a note on what each number means. No prompts, paths or
   session ids.
2. The analyst reads that file and nothing else, and writes `~/.claude/task-eta/insights.json`:

```json
{"v": 1, "generated": "2026-10-26T09:00:00+01:00", "period": "19-26 October",
 "headline": "One sentence", "items": [{"title": "…", "body": "…", "kind": "trend|record|tip|warning"}]}
```

3. TaskETA shows it in the dashboard ("Weekly analysis", with "Read the analysis").

The labels in `insights-input.json` reach the model like any conversation, so leave this off if a project name
must not.

## Setting it up

In the Claude desktop app, create a scheduled task (for example every Monday at 9, cron `0 9 * * 1`) with the
prompt below, replacing `<repo>` with the path of this folder. It runs only while the app is open; if it is
closed at that time, it runs at the next start.

```text
You are an outside analyst of a user's Claude Code task times, for their TaskETA app. You have no other
context and must not look for any: no chats, no prompts, no repositories, no index. Only the numbers
prepared for you.

1. Prepare the numbers with this command, and only this one:
   python3 -I <repo>/widget/insights/export.py
2. Read ONLY ~/.claude/task-eta/insights-input.json. Open no other file. Its "about" section says what
   each number means.
3. Find 4 to 6 useful observations, with exact numbers from the file: the trend against the week before
   (if previous_week has no estimated tasks, say so once and make no comparison); where the estimates
   miss most (kind of work, model, project, hour of day) and by how much; a record or milestone; at least
   one concrete tip to estimate better or organise the work. Invent nothing. Use project and model names
   as they are.
4. Write ~/.claude/task-eta/insights.json (UTF-8), exactly in this form, no markdown:
   {"v": 1, "generated": "<ISO 8601 with time zone>", "period": "<e.g. 19-26 October>",
    "headline": "<one sentence, at most 70 characters>",
    "items": [{"title": "<at most 45 characters>", "body": "<1 or 2 sentences, at most 220 characters>",
               "kind": "trend|record|tip|warning"}]}
   In the language given by "language" in the file ("en" or "it"): plain words, short sentences, readable
   round numbers ("1.3 times the estimate", "62%").
5. Check the file is valid JSON:
   python3 -c "import json, os; d=json.load(open(os.path.expanduser('~/.claude/task-eta/insights.json'))); assert d['headline'] and d['items']; print(len(d['items']), 'items')"
   If it fails, fix the file and try again.
6. Reply with the headline only.
```

To run it by hand: `python3 export.py`, then "Run now" on the scheduled task.
