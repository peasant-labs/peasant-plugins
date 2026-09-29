#!/usr/bin/env bash
# /peasant — open the CURRENT Claude Code session's transcript.
#
# `peasant open` does the work: it records the session, starts the web
# dashboard when none is running, opens the transcript in the browser, and
# prints the result. This script finds the session id, runs that command, and
# passes its output on. It never opens the browser itself.
#
# Two modes:
#
#   open-session.sh --hook          Hook mode, from hooks/hooks.json. Reads the
#                                   UserPromptExpansion JSON on stdin and prints
#                                   one {"continue":false,"stopReason":"..."}
#                                   line on stdout, so Claude processes nothing
#                                   and the lines show as a user-facing note.
#
#   open-session.sh [<session-id>]  Plain mode, the skill fallback when hooks
#                                   are disabled. Prints the lines of
#                                   `peasant open`: two on stdout on success,
#                                   one on stderr on failure.
#
# Both modes exit 0 on every outcome. The output reports a failure, so the
# hook does not render as an error and the skill fallback can relay it.
set -uo pipefail

MODE=plain
if [ "${1:-}" = "--hook" ]; then
  MODE=hook
  input="$(cat)"
  SID="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
else
  SID="${1:-}"
fi

# report LINE: print one line of this script's own in the shape of the mode,
# then exit 0. In hook mode the line becomes the stopReason: control
# characters are dropped, and backslashes and double quotes are escaped.
report() {
  if [ "$MODE" = hook ]; then
    local reason
    reason="$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    printf '{"continue":false,"stopReason":"%s"}\n' "$reason"
  else
    printf '%s\n' "$1" >&2
  fi
  exit 0
}

command -v peasant >/dev/null 2>&1 || report "ERROR: the 'peasant' binary is not on your PATH"

# Fall back to the newest transcript for this directory when no session id was
# supplied (older Claude Code, or a skill synced from claude.ai).
if [ -z "$SID" ]; then
  dir="$HOME/.claude/projects/$(printf '%s' "$PWD" | sed 's#/#-#g')"
  SID="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1 | xargs -r -n1 basename 2>/dev/null | sed 's/\.jsonl$//')"
fi
[ -n "$SID" ] || report "ERROR: no Claude Code transcript found for this directory"

errors="$(mktemp "${TMPDIR:-/tmp}/peasant-open.XXXXXX")" || report "ERROR: could not create a temporary file for the output of 'peasant open'"
trap 'rm -f "$errors"' EXIT

# failure_line DEFAULT: the one line to show when `peasant open` did not give
# its result the normal way. Its own failure line wins wherever it is on stderr
# (a notice may come first). Otherwise this peasant has no `open` command, or
# the command stopped before it ran: a flag error exits 1 with usage on
# stderr, even with --hook. DEFAULT is the reason when stderr names none.
failure_line() {
  local line
  line="$(grep -m1 '^peasant: ' "$errors")"
  if [ -n "$line" ]; then
    printf '%s' "$line"
  elif grep -q 'unknown command "open"' "$errors"; then
    printf '%s' 'peasant: open failed: this peasant has no open command; fix: update peasant with `peasant upgrade`'
  else
    line="$(sed -n '/[^[:space:]]/{p;q;}' "$errors")"
    line="${line#Error: }"
    printf 'peasant: open failed: %s; fix: run `peasant open --session %s` in a terminal to see the full error' "${line:-$1}" "$SID"
  fi
}

if [ "$MODE" = hook ]; then
  out="$(peasant open --session "$SID" --hook </dev/null 2>"$errors")"
  status=$?
  # `peasant open --hook` owns the hook response: one JSON object on one line,
  # on every outcome. Pass it through unchanged.
  if [ "$status" -eq 0 ]; then
    case "$out" in
      *$'\n'*) ;;
      '{'*'}') printf '%s\n' "$out"; exit 0 ;;
    esac
  fi
  report "$(failure_line "peasant open printed no hook response (exit status $status)")"
fi

# Plain mode: the lines on stdout pass straight through.
peasant open --session "$SID" </dev/null 2>"$errors"
status=$?
if [ "$status" -eq 0 ]; then
  cat "$errors" >&2
  exit 0
fi
report "$(failure_line "peasant open exited with status $status and printed no error")"
