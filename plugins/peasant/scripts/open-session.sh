#!/usr/bin/env bash
# /peasant — record the CURRENT Claude Code session and open its transcript.
#
# Two modes:
#
#   open-session.sh <session-id>   Plain mode. Used by the skill's fallback
#                                  block when hooks are disabled. Writes
#                                  progress + the URL to stderr, exits 0.
#
#   open-session.sh --hook         Hook mode. Reads the UserPromptExpansion
#                                  JSON on stdin and prints a JSON object with
#                                  `continue: false` and a `stopReason`, so
#                                  Claude processes nothing (zero tokens) and
#                                  the message renders as a normal user-facing
#                                  note instead of a blocked-hook warning.
#
# Either mode: record only this session, ensure the dashboard is up, open the
# transcript, report the URL.
set -uo pipefail

PORT=8690
BASE="http://localhost:${PORT}"

MODE=plain
if [ "${1:-}" = "--hook" ]; then
  MODE=hook
  input="$(cat)"
  SID="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
else
  SID="${1:-}"
fi

# The message is accumulated with literal \n escapes: they are valid JSON
# string escapes in hook mode and are expanded for the terminal in plain mode.
MSG=""
say() {
  if [ -n "$MSG" ]; then MSG="$MSG\n$*"; else MSG="$*"; fi
}

# Print the accumulated message in the shape the current mode needs. Always
# exits 0 — nothing here is an error, and the browser already opened.
emit() {
  if [ "$MODE" = hook ]; then
    printf '{"continue":false,"stopReason":"%s"}\n' "$MSG"
  else
    printf '%b\n' "$MSG" >&2
  fi
  exit 0
}

fail() { say "ERROR: $1"; emit; }

command -v peasant >/dev/null 2>&1 || fail "the 'peasant' binary is not on your PATH"

# Fall back to the newest transcript for this directory when no session id was
# supplied (older Claude Code, or a skill synced from claude.ai).
if [ -z "$SID" ]; then
  dir="$HOME/.claude/projects/$(printf '%s' "$PWD" | sed 's#/#-#g')"
  SID="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1 | xargs -r -n1 basename 2>/dev/null | sed 's/\.jsonl$//')"
fi
[ -n "$SID" ] || fail "no Claude Code transcript found for this directory"

# 1. Record ONLY this session. An empty JSON array means it is not stored yet.
stored="$(peasant sessions list --session "$SID" --json 2>/dev/null)"
if printf '%s' "$stored" | grep -q '"id"'; then
  say "Refreshing this session in peasant…"
else
  say "Ingesting this session into peasant…"
fi
peasant harvest --session "$SID" --force >/dev/null 2>&1

# 2. projectHash, for the transcript deep link.
hash="$(peasant sessions list --session "$SID" --json 2>/dev/null \
  | sed -n 's/.*"projectHash": *"\([^"]*\)".*/\1/p' | head -1)"

# 3. Dashboard.
if ! curl -sf -o /dev/null "${BASE}/api/v1/health" 2>/dev/null; then
  say "Starting the peasant dashboard on port ${PORT}…"
  peasant web start --no-browser >/dev/null 2>&1
  for _ in $(seq 1 40); do
    curl -sf -o /dev/null "${BASE}/api/v1/health" 2>/dev/null && break
    sleep 0.25
  done
fi

# 4. Open the transcript.
if [ -n "$hash" ]; then
  url="${BASE}/projects/${hash}/${SID}"
else
  url="${BASE}/"
fi

case "$(uname -s)" in
  Darwin) open "$url" >/dev/null 2>&1 || true ;;
  Linux)  xdg-open "$url" >/dev/null 2>&1 || true ;;
  *)      ;;  # headless or another OS: the printed URL is the deliverable
esac

say "URL: ${url}"
emit
