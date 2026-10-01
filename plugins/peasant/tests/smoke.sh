#!/usr/bin/env bash
# Smoke checks for the peasant plugin: the manifests, skill and hook are
# well-formed, and scripts/open-session.sh behaves as a shim over
# `peasant open` in every case under tests/fixtures/cases/. The cases run
# against a stub peasant, so no real peasant binary is needed.
set -uo pipefail

here="$(cd "$(dirname "$0")/../../.." && pwd)"   # repo root
plugin="$here/plugins/peasant"
script="$plugin/scripts/open-session.sh"
fixtures="$plugin/tests/fixtures"
fail=0

check() { if eval "$2" >/dev/null 2>&1; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

echo "== peasant plugin smoke =="
check "marketplace.json is valid JSON" "python3 -c 'import json;json.load(open(\"$here/.claude-plugin/marketplace.json\"))'"
check "plugin.json is valid JSON" "python3 -c 'import json;json.load(open(\"$plugin/.claude-plugin/plugin.json\"))'"
check "SKILL.md begins with frontmatter" "head -1 \"$plugin/SKILL.md\" | grep -q '^---$'"
check "SKILL.md declares user-only trigger" "grep -q 'disable-model-invocation: true' \"$plugin/SKILL.md\""
check "SKILL.md runs the bundled script" "grep -q 'CLAUDE_PLUGIN_ROOT}/scripts/open-session.sh' \"$plugin/SKILL.md\""
check "SKILL.md pre-approves the bundled script" "grep -q 'allowed-tools:.*open-session.sh' \"$plugin/SKILL.md\""
check "SKILL.md relays no URL: line" "! grep -q 'URL:' \"$plugin/SKILL.md\""
check "SKILL.md keeps raw arguments out of executable fences" "python3 \"$plugin/tests/assert-safe-fallback.py\" \"$plugin/SKILL.md\""
check "open-session.sh exists and is executable" "[ -x \"$script\" ]"
check "open-session.sh parses" "bash -n \"$script\""
check "open-session.sh leaves the work to peasant" "! grep -Eq 'sessions list|projectHash|harvest|web start|hooks install' \"$script\""
check "hooks.json is valid JSON" "python3 -c 'import json;json.load(open(\"$plugin/hooks/hooks.json\"))'"
check "hooks.json targets the peasant command" "grep -q 'UserPromptExpansion' \"$plugin/hooks/hooks.json\" && grep -q 'peasant' \"$plugin/hooks/hooks.json\""
check "hooks.json calls the bundled script in hook mode" "grep -q 'open-session.sh --hook' \"$plugin/hooks/hooks.json\""

# Each directory under tests/fixtures/cases/ is one run of open-session.sh
# with an empty HOME, TMPDIR and working directory, and a PATH that holds only
# the tools below, the stub browser openers (tests/fixtures/bin/open, xdg-open)
# and the stub peasant (tests/fixtures/bin/peasant). A case has these files:
#
#   args           the script's arguments, one per line, so a line may be an
#                  empty argument (--hook first: hook mode)
#   stdin          the hook input (absent: a line peasant must never read).
#                  {session} in it is the path of a session directory whose
#                  name holds a space, a double quote and a backslash, escaped
#                  as JSON escapes it
#   no-peasant     run with no peasant on PATH
#   transcripts    Claude Code transcript names, oldest first, created in
#                  ~/.claude/projects/<cwd> for the newest-transcript fallback.
#                  A fallback case puts the newest in the middle by name, so
#                  name order cannot pass for time order.
#   stub.stdout, stub.stderr, stub.exit
#                  what the stub peasant prints, and its exit status
#   expect.stdout, expect.stderr
#                  the exact output of the script (absent: empty)
#   expect.argv    the arguments the stub received, one per line (absent: the
#                  stub must not run)
#   expect.cwd     the directory the stub ran in: session (the {session}
#                  directory) or work (the script's working directory)
#
# Every run must also exit 0 and never call a browser opener (peasant open
# opens the browser itself). peasant must get an empty pipe or file on stdin,
# as peasant would see it (not a character device, not closed), and no
# descriptor above 2: the dashboard peasant starts would inherit it, and one
# that points at the script's stdout would hold the hook's output open. The runner closes
# descriptors 3 to 9 before it starts the script. The script must leave
# nothing in TMPDIR. A hook run must print one
# hook response with continue:false and a stopReason of at most two lines, and
# a plain run at most two lines in all.
#
# The tools the script may run, taken from /usr/bin and /bin first so a macOS
# run uses the system's BSD tools and bash. A tool the script starts using
# must be added here.
script_tools="bash basename cat grep head ls mktemp rm sed tr xargs"

# Every case is named here, and every case directory must be named here. A
# name:file entry also requires that file, where deleting it would leave the
# case passing as a copy of another.
required_cases="$(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))))' "$fixtures/required-cases.yaml")"
required_names=" "
for entry in $required_cases; do
  name="${entry%%:*}"
  required_names="$required_names$name "
  check "fixture case $name exists" "[ -d \"$fixtures/cases/$name\" ]"
  [ "$name" = "$entry" ] || check "fixture case $name has ${entry#*:}" "[ -f \"$fixtures/cases/$name/${entry#*:}\" ]"
done
for dir in "$fixtures"/cases/*/; do
  name="$(basename "$dir")"
  case "$required_names" in
    *" $name "*) ;;
    *) echo "FAIL: fixture case $name is not named in required_cases"; fail=1 ;;
  esac
done

# The hook response contract, read from stdin.
hook_response_ok='
import json, sys
text = sys.stdin.read()
assert text.endswith("\n") and text.count("\n") == 1, "not exactly one line"
response = json.loads(text)
assert response["continue"] is False
assert len(response["stopReason"].split("\n")) <= 2, "stopReason has more than two lines"
'

# The directory Claude Code keeps a working directory's transcripts in: the
# path with every non-alphanumeric character replaced by "-".
project_dir_name='
import re, sys
print(re.sub(r"[^A-Za-z0-9]", "-", sys.argv[1]))
'

# The hook input with {session} replaced by the JSON-escaped path in argv[1].
fill_session='
import json, sys
sys.stdout.write(sys.stdin.read().replace("{session}", json.dumps(sys.argv[1])[1:-1]))
'

# A session directory name that JSON has to escape.
session_name='my "repo" \dir'

# case_fail NAME REASON: report one failed case.
case_fail() { echo "FAIL: case $1: $2"; fail=1; }

tmp=""
trap '[ -z "$tmp" ] || rm -rf "$tmp"' EXIT
trap '[ -z "$tmp" ] || rm -rf "$tmp"; exit 130' INT TERM

run_case() {
  local dir=$1 name work session projects tool name_line arg stdin status stream expect want i n ok=1
  local -a args=() transcripts=()
  name="$(basename "$dir")"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/peasant-smoke.XXXXXX")"
  mkdir -p "$tmp/bin" "$tmp/home" "$tmp/tmp" "$tmp/work/my.app_dir" "$tmp/session/$session_name"
  work="$(cd "$tmp/work/my.app_dir" && pwd -P)"   # the script sees the physical path
  session="$(cd "$tmp/session/$session_name" && pwd -P)"

  for tool in $script_tools; do
    # An assignment, not a one-command prefix: bash 3.2 keeps its hashed
    # paths for a prefix, and the runner has already run bash and grep.
    ln -s "$(PATH="/usr/bin:/bin:$PATH"; command -v "$tool")" "$tmp/bin/$tool"
  done
  ln -s "$fixtures/bin/open" "$tmp/bin/open"
  ln -s "$fixtures/bin/open" "$tmp/bin/xdg-open"
  [ -f "$dir/no-peasant" ] || ln -s "$fixtures/bin/peasant" "$tmp/bin/peasant"

  if [ -f "$dir/transcripts" ]; then
    projects="$tmp/home/.claude/projects/$(python3 -c "$project_dir_name" "$work")"
    mkdir -p "$projects"
    while read -r name_line; do transcripts+=("$name_line"); done <"$dir/transcripts"
    # Create the newest first and give access times the reverse order, so only
    # the modification time puts the transcripts oldest to newest.
    n=${#transcripts[@]}
    i=$n
    while [ "$i" -gt 0 ]; do
      i=$((i - 1))
      : >"$projects/${transcripts[i]}.jsonl"
      touch -m -t "20200101$(printf '%02d' $((i + 1)))00" "$projects/${transcripts[i]}.jsonl"
      touch -a -t "20200102$(printf '%02d' $((n - i)))00" "$projects/${transcripts[i]}.jsonl"
    done
  fi

  if [ -f "$dir/args" ]; then
    while IFS= read -r arg; do args+=("$arg"); done <"$dir/args"
  fi
  stdin="$dir/stdin"
  if [ -f "$stdin" ]; then
    python3 -c "$fill_session" "$session" <"$dir/stdin" >"$tmp/stdin"
    stdin="$tmp/stdin"
  else
    stdin="$tmp/stdin"
    printf 'the script must not pass this on to peasant\n' >"$stdin"
  fi

  (cd "$work" && env -i HOME="$tmp/home" PATH="$tmp/bin" TMPDIR="$tmp/tmp" \
    PEASANT_STUB_CASE="$dir" PEASANT_STUB_ARGV="$tmp/argv" PEASANT_STUB_STDIN="$tmp/stub-stdin" \
    PEASANT_STUB_FDS="$tmp/stub-fds" PEASANT_STUB_CWD="$tmp/stub-cwd" PEASANT_STUB_BROWSER="$tmp/browser" \
    "$script" ${args[@]+"${args[@]}"} <"$stdin" >"$tmp/stdout" 2>"$tmp/stderr" \
    3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-)
  status=$?

  [ "$status" -eq 0 ] || { case_fail "$name" "exit status $status, want 0"; ok=0; }
  for stream in stdout stderr; do
    expect="$dir/expect.$stream"
    [ -f "$expect" ] || expect=/dev/null
    if ! cmp -s "$expect" "$tmp/$stream"; then
      case_fail "$name" "$stream differs from expect.$stream:"
      diff -u "$expect" "$tmp/$stream" | sed 's/^/    /'
      ok=0
    fi
  done
  if [ -f "$dir/expect.argv" ]; then
    if ! cmp -s "$dir/expect.argv" "$tmp/argv" 2>/dev/null; then
      case_fail "$name" "peasant was not run exactly once with expect.argv"
      ok=0
    fi
  elif [ -e "$tmp/argv" ]; then
    case_fail "$name" "peasant ran, but the case expects it not to"; ok=0
  fi
  if [ -f "$dir/expect.cwd" ]; then
    case "$(cat "$dir/expect.cwd")" in
      session) want="$session" ;;
      work) want="$work" ;;
      *) want="(expect.cwd names neither session nor work)" ;;
    esac
    [ "$(cat "$tmp/stub-cwd" 2>/dev/null)" = "$want" ] \
      || { case_fail "$name" "peasant ran in $(cat "$tmp/stub-cwd" 2>/dev/null), want $want"; ok=0; }
  fi
  [ -z "$(ls -A "$tmp/tmp")" ] || { case_fail "$name" "the script left files in TMPDIR: $(ls -A "$tmp/tmp" | tr '\n' ' ')"; ok=0; }
  [ ! -e "$tmp/browser" ] || { case_fail "$name" "the script opened the browser itself"; ok=0; }
  [ ! -s "$tmp/stub-stdin" ] || { case_fail "$name" "peasant's stdin was not an empty pipe: $(head -1 "$tmp/stub-stdin")"; ok=0; }
  [ ! -e "$tmp/stub-fds" ] || { case_fail "$name" "peasant got open descriptors: $(tr '\n' ' ' <"$tmp/stub-fds")"; ok=0; }
  if [ "${args[0]:-}" = "--hook" ]; then
    python3 -c "$hook_response_ok" <"$tmp/stdout" >/dev/null 2>&1 \
      || { case_fail "$name" "stdout is not one hook response with continue:false and a stopReason of at most two lines"; ok=0; }
  elif [ "$(cat "$tmp/stdout" "$tmp/stderr" | wc -l)" -gt 2 ]; then
    case_fail "$name" "plain mode printed more than two lines"; ok=0
  fi

  [ "$ok" -eq 0 ] || echo "ok: case $name"
  rm -rf "$tmp"
  tmp=""
}

for dir in "$fixtures"/cases/*/; do
  run_case "${dir%/}"
done

# The stub's flags must still be the real command's. This runs only when the
# peasant on PATH has `open`, and asks it for help only.
if peasant open --help >/dev/null 2>&1; then
  check "the installed peasant open takes --session and --hook" \
    "peasant open --help | grep -Eq -- '^ +--session string ' && peasant open --help | grep -Eq -- '^ +--hook( |\$)'"
else
  echo "skip: no peasant with the open command on PATH (cannot check the stub's flags)"
fi

if command -v claude >/dev/null 2>&1; then
  check "claude plugin validate passes" "(cd \"$here\" && claude plugin validate .)"
else
  echo "skip: claude CLI not on PATH (cannot run 'claude plugin validate')"
fi

if [ "$fail" -eq 0 ]; then echo "ALL OK"; else echo "SMOKE FAILED"; fi
exit "$fail"
