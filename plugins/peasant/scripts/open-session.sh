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
# Anything else peasant writes to stderr, such as a one-time config migration
# notice, is dropped, so the output stays at most two lines.
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
# supplied (older Claude Code, or a skill synced from claude.ai). Claude Code
# names the directory after the path with every non-alphanumeric character
# replaced by '-'. This matches it for ASCII paths; Claude Code also shortens
# names over 200 characters, which this fallback does not.
if [ -z "$SID" ]; then
  dir="$HOME/.claude/projects/$(printf '%s' "$PWD" | LC_ALL=C sed 's#[^A-Za-z0-9]#-#g')"
  SID="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1 | xargs -r -n1 basename 2>/dev/null | sed 's/\.jsonl$//')"
fi
[ -n "$SID" ] || report "ERROR: no Claude Code transcript found for this directory"

# failure_line DEFAULT: the one line to show when `peasant open` did not give
# its result the normal way. Its own failure line wins wherever it is on stderr
# (a notice may come first). Otherwise this peasant has no `open` command, or
# the command stopped without a result line: a flag error (exit 1 with usage
# on stderr, even with --hook), a crash, or a kill. It reads the captured
# $errors and the call's $args. DEFAULT is the reason when stderr names none.
failure_line() {
  local line
  line="$(printf '%s\n' "$errors" | grep -m1 '^peasant: ')"
  if [ -n "$line" ]; then
    printf '%s' "$line"
  elif printf '%s\n' "$errors" | grep -q 'unknown command "open"'; then
    printf '%s' 'peasant: open failed: this peasant has no open command; fix: run `peasant upgrade`, or `peasant upgrade --prerelease` if that finds no newer release (Homebrew installs get stable releases only; a peasant older than v0.5.0 has no upgrade command, so reinstall it from https://github.com/peasant-labs/peasant/releases)'
  else
    # The error itself, not a notice printed before it.
    line="$(printf '%s\n' "$errors" | grep -m1 -E '^(Error|panic): ')"
    [ -n "$line" ] || line="$(printf '%s\n' "$errors" | sed -n '/[^[:space:]]/{p;q;}')"
    line="${line#Error: }"
    printf 'peasant: open failed: %s; fix: run `peasant open %s` in a terminal to see the full error' "${line:-$1}" "${args[*]}"
  fi
}

# Run `peasant open`. Its stdout passes straight through, and in hook mode it
# is the hook response, which `peasant open --hook` prints on every outcome
# once its flags parse. Its stderr is kept only to find a failure line in, and
# is dropped on success. Its stdin is an empty pipe: not this script's stdin,
# which in plain mode may be a terminal that a prompt would wait on, and not
# /dev/null, a character device that peasant takes for a terminal. peasant
# gets no fd 3, so a dashboard it starts cannot hold this script's stdout open.
args=(--session "$SID")
[ "$MODE" = plain ] || args+=(--hook)
{ errors="$(: | peasant open "${args[@]}" 2>&1 >&3 3>&-)"; } 3>&1
status=$?
[ "$status" -ne 0 ] || exit 0
report "$(failure_line "peasant exited with status $status and printed no error")"
