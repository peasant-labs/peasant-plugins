---
name: peasant
description: Harvest THIS Claude Code session into peasant and open its transcript in the local web dashboard.
disable-model-invocation: true
allowed-tools: Bash(peasant *) Bash(curl *) Bash(xdg-open *) Bash(ls *) Bash(sed *) Bash(head *) Bash(basename *) Bash(xargs *) Bash(printf *) Bash(pwd)
---

# /peasant — record and open this session

Harvest the CURRENT Claude Code session into your local peasant store, make sure
`peasant web` is running, and open THIS session's transcript in the dashboard.

Prerequisite: the `peasant` binary must be installed and on your PATH
(https://github.com/peasant-labs/peasant). This plugin does not install it.

Scope: this records ONLY the session that ran `/peasant`. It never harvests the
whole project.

## Discovery (read-only — runs automatically, no side effects)

Below is this session's id, whether it is already stored (with its projectHash),
and whether the dashboard is already running.

```!
CWD="$(pwd)"
ENC="$(printf '%s' "$CWD" | sed 's#/#-#g')"
DIR="$HOME/.claude/projects/$ENC"
SID="$(ls -t "$DIR"/*.jsonl 2>/dev/null | head -1 | xargs -r -n1 basename 2>/dev/null | sed 's/\.jsonl$//')"
echo "session_id=${SID:-UNKNOWN}"
if curl -sf -o /dev/null "http://localhost:8690/api/v1/health" 2>/dev/null; then
  echo "web_up=yes"
else
  echo "web_up=no"
fi
if [ -n "$SID" ]; then
  echo "stored_session_json:"
  peasant sessions list --session "$SID" --json 2>/dev/null
fi
```

Interpret the discovery output:

- If `session_id` is `UNKNOWN`: tell the user no active transcript was found for
  this directory, and stop.
- `stored_session_json` is a JSON array. An EMPTY array (`[]`) means this session
  is NOT stored yet. A one-element array means it IS stored; that element's
  `projectHash` is the value you need for the URL.

## Step 1 — Harvest ONLY this session

- If the session is NOT stored (empty array): ask the user with AskUserQuestion —
  "Record this session into peasant now?" (Yes / No). If No, stop. If Yes, run:

      peasant harvest --session SESSION_ID

- If the session IS stored: refresh silently (do NOT prompt):

      peasant harvest --session SESSION_ID --force

Always pass `--session SESSION_ID`. Never run a project-wide or `--all` harvest.

## Step 2 — Get this session's projectHash

After harvesting, the session is in the store. Read its projectHash:

    peasant sessions list --session SESSION_ID --json

Take `projectHash` from the single returned element. (If you already have it from
discovery for an already-stored session, reuse that value.)

## Step 3 — Ensure the dashboard is running

- If `web_up=yes`: reuse it (port 8690).
- If `web_up=no`: start it in the background without opening its own tab:

      peasant web start --no-browser

  It listens on port 8690.

## Step 4 — Open this session's transcript

The transcript URL is:

    http://localhost:8690/projects/PROJECT_HASH/SESSION_ID

Open it, then print it for the user:

    xdg-open "http://localhost:8690/projects/PROJECT_HASH/SESSION_ID"

Fallback: if `projectHash` is still unavailable, open the dashboard root
`http://localhost:8690/` and print that URL instead.

## Done

Tell the user: session recorded (or refreshed), dashboard running, transcript
opened — and print the final URL so they can click it.
