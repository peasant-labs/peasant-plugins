#!/usr/bin/env bash
# /peasant — record the CURRENT Claude Code session and open its transcript.
#
# Two modes:
#
#   open-session.sh <session-id>   Plain mode. Used by the skill's fallback
#                                  block when hooks are disabled. Prints
#                                  progress + the URL, always exits 0.
#
#   open-session.sh --hook         Hook mode. Reads the UserPromptExpansion
#                                  JSON on stdin, takes the session id from it,
#                                  and exits 2 so the expansion is BLOCKED and
#                                  Claude is never invoked. Progress + the URL
#                                  go to stderr, which is shown to the user.
#                                  This is the zero-token path.
#
# Either mode: record only this session, ensure the dashboard is up, open the
# transcript, print the URL.
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

# Progress goes to stderr: plain mode merges it into the skill's injected text,
# hook mode uses stderr as the blocking message. Keep lines short and human.
say()  { printf '%s\n' "$*" >&2; }
fail() {
  printf 'ERROR: %s\n' "$1" >&2
  [ "$MODE" = hook ] && exit 2   # still block: never spend a model turn on a failure
  exit 0
}

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
[ "$MODE" = hook ] && exit 2   # block the expansion: the model never runs
exit 0
