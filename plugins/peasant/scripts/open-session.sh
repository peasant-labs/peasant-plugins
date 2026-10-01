#!/usr/bin/env bash
# /peasant — open the CURRENT Claude Code session's transcript.
# /peasant auto — publish this repository's sessions on every git push.
#
# peasant does the work. `peasant open` records the session, starts the web
# dashboard when none is running, opens the transcript in the browser, and
# prints the result. `peasant village auto` saves an auto-publish rule for the
# repository with the collectives the developer published to last, installs
# its git hook, and prints one line. This script picks the command, runs it,
# and passes its output on. It never opens the browser and never picks the
# collectives itself.
#
# The command's arguments pick the command: exactly `auto` runs
# `peasant village auto` in the session's directory. Any other arguments, or
# none, open the session.
#
# Two modes:
#
#   open-session.sh --hook          Hook mode, from hooks/hooks.json. Reads the
#                                   UserPromptExpansion JSON on stdin (its
#                                   session_id, command_args and cwd) and
#                                   prints one {"continue":false,"stopReason":"..."}
#                                   line on stdout, so Claude processes nothing
#                                   and the lines show as a user-facing note.
#
#   open-session.sh [--args <arguments>] [<session-id>]
#                                   Plain mode, the skill fallback when hooks
#                                   are disabled, run in the session's
#                                   directory. Prints the lines of peasant:
#                                   the result on stdout (two lines for open,
#                                   one for auto), or one line on stderr on
#                                   failure.
#
# Anything else peasant writes to stderr, such as a one-time config migration
# notice, is dropped, so the output stays at most two lines.
#
# Both modes exit 0 on every outcome. The output reports a failure, so the
# hook does not render as an error and the skill fallback can relay it.
set -uo pipefail

# hook_field NAME: the string value of NAME in the hook input, with the JSON
# escapes \\, \" and \/ undone. Empty when the input has no NAME.
hook_field() {
  local escaped remaining
  escaped="$(printf '%s' "$input" \
    | LC_ALL=C sed -n -E 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -1)"
  # Only the escapes decoded below may reach a repository or session decision.
  # Removing supported pairs first distinguishes a literal backslash followed
  # by "u" from a Unicode escape. Unsupported escapes never become a guess.
  remaining="$(printf '%s' "$escaped" | LC_ALL=C sed -E 's/\\[\\"/]//g')"
  case "$remaining" in *\\*) return 1 ;; esac
  printf '%s' "$escaped" | LC_ALL=C sed -E 's/\\(.)/\1/g'
}

MODE=plain
ARGS=""
DIR=""
UNSUPPORTED_ESCAPE=false
if [ "${1:-}" = "--hook" ]; then
  MODE=hook
  input="$(cat)"
  SID="$(hook_field session_id)" || UNSUPPORTED_ESCAPE=true
  ARGS="$(hook_field command_args)" || UNSUPPORTED_ESCAPE=true
  DIR="$(hook_field cwd)" || UNSUPPORTED_ESCAPE=true
else
  if [ "${1:-}" = "--args" ]; then
    ARGS="${2:-}"
    shift
    [ "$#" -eq 0 ] || shift
  fi
  SID="${1:-}"
fi

# report LINE [FD]: print one line in the shape of the mode, then exit 0. In
# hook mode the line becomes the stopReason: control characters are dropped,
# and backslashes and double quotes are escaped. In plain mode the line goes to
# FD: stderr (2, the default) for a failure, stdout (1) for a result.
report() {
  if [ "$MODE" = hook ]; then
    local reason
    reason="$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    printf '{"continue":false,"stopReason":"%s"}\n' "$reason"
  else
    printf '%s\n' "$1" >&"${2:-2}"
  fi
  exit 0
}

if [ "$UNSUPPORTED_ESCAPE" = true ]; then
  report "ERROR: the hook input uses an unsupported JSON escape; no command ran; run peasant open or peasant village auto in this repository in a terminal"
fi

command -v peasant >/dev/null 2>&1 || report "ERROR: the 'peasant' binary is not on your PATH"

# run_peasant ARGS...: run `peasant ARGS...`. Its stdout goes to this
# function's fd 3, its stderr is kept in $errors, and its exit status in
# $status. Its stdin is an empty pipe: not this script's stdin, which in plain
# mode may be a terminal that a prompt would wait on, and not /dev/null, a
# character device that peasant takes for a terminal. peasant gets no fd 3, so
# a dashboard it starts cannot hold this script's stdout open.
run_peasant() {
  errors="$(: | peasant "$@" 2>&1 >&3 3>&-)"
  status=$?
}

# error_reason: the error peasant printed on stderr, not a notice printed
# before it. That is its first Error: or panic: line, without the Error:
# prefix, or else its first line that is not blank.
error_reason() {
  local line
  line="$(printf '%s\n' "$errors" | grep -m1 -E '^(Error|panic): ')"
  [ -n "$line" ] || line="$(printf '%s\n' "$errors" | sed -n '/[^[:space:]]/{p;q;}')"
  printf '%s' "${line#Error: }"
}

upgrade='fix: run `peasant upgrade`, or `peasant upgrade --prerelease` if that finds no newer release (Homebrew installs get stable releases only; a peasant older than v0.5.0 has no upgrade command, so reinstall it from https://github.com/peasant-labs/peasant/releases)'

# auto_failure_line DEFAULT: the one line to show when `peasant village auto`
# gave no result line. It exits 0 with a result line on success. A peasant
# without the command prints the help of `peasant village` and also exits 0.
# A refusal is one error on stderr that says what was changed and names its
# fix, and that line is enough when it is all peasant printed. Anything else,
# such as a crash or guidance printed before the error, gets a fix that shows
# the full output. DEFAULT is the reason when stderr names none.
auto_failure_line() {
  local reason fix='; fix: run `peasant village auto` in this repository in a terminal to see the full output'
  if [ "$status" -eq 0 ]; then
    printf 'peasant: auto failed: this peasant has no village auto command; %s' "$upgrade"
    return
  fi
  reason="$(error_reason)"
  case "$reason" in
    "village auto: "*) [ "$(printf '%s\n' "$errors" | grep -c '[^[:space:]]')" -ne 1 ] || fix="" ;;
  esac
  reason="${reason#village auto: }"
  printf 'peasant: auto failed: %s%s' "${reason:-$1}" "$fix"
}

# /peasant auto. peasant's stdout is kept in a temporary file to be checked
# for the result line, and the file is removed on exit.
if [ "$ARGS" = auto ]; then
  if [ -n "$DIR" ]; then
    cd -- "$DIR" 2>/dev/null || report "ERROR: this session's directory is not reachable: $DIR"
  fi
  result="$(mktemp "${TMPDIR:-/tmp}/peasant-auto.XXXXXX")" || report "ERROR: cannot create a temporary file for peasant's output"
  trap 'rm -f "$result"' EXIT
  { run_peasant village auto; } 3>"$result"
  line="$(head -1 "$result")"
  if [ "$status" -eq 0 ]; then
    case "$line" in "peasant: "*) report "$line" 1 ;; esac
  fi
  report "$(auto_failure_line "peasant exited with status $status and printed no error")"
fi

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
    printf 'peasant: open failed: this peasant has no open command; %s' "$upgrade"
  else
    line="$(error_reason)"
    printf 'peasant: open failed: %s; fix: run `peasant open %s` in a terminal to see the full error' "${line:-$1}" "${args[*]}"
  fi
}

# /peasant. The stdout of `peasant open` passes straight through, and in hook
# mode it is the hook response, which `peasant open --hook` prints on every
# outcome once its flags parse. Its stderr is kept only to find a failure line
# in, and is dropped on success.
args=(--session "$SID")
[ "$MODE" = plain ] || args+=(--hook)
{ run_peasant open "${args[@]}"; } 3>&1
[ "$status" -ne 0 ] || exit 0
report "$(failure_line "peasant exited with status $status and printed no error")"
