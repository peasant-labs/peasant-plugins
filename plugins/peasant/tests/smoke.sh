#!/usr/bin/env bash
# Happy-path smoke checks for the peasant plugin.
# Verifies the plugin is well-formed and its runtime prerequisite is present.
# No unhappy-path coverage by design (MVP).
set -uo pipefail

here="$(cd "$(dirname "$0")/../../.." && pwd)"   # repo root
fail=0

check() { if eval "$2" >/dev/null 2>&1; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

echo "== peasant plugin smoke =="
check "peasant binary on PATH" "command -v peasant"
check "marketplace.json is valid JSON" "python3 -c 'import json;json.load(open(\"$here/.claude-plugin/marketplace.json\"))'"
check "plugin.json is valid JSON" "python3 -c 'import json;json.load(open(\"$here/plugins/peasant/.claude-plugin/plugin.json\"))'"
check "SKILL.md begins with frontmatter" "head -1 \"$here/plugins/peasant/SKILL.md\" | grep -q '^---$'"
check "SKILL.md declares user-only trigger" "grep -q 'disable-model-invocation: true' \"$here/plugins/peasant/SKILL.md\""
check "SKILL.md runs the bundled script" "grep -q 'CLAUDE_PLUGIN_ROOT}/scripts/open-session.sh' \"$here/plugins/peasant/SKILL.md\""
check "SKILL.md pre-approves the bundled script" "grep -q 'allowed-tools:.*open-session.sh' \"$here/plugins/peasant/SKILL.md\""
check "open-session.sh exists and is executable" "[ -x \"$here/plugins/peasant/scripts/open-session.sh\" ]"
check "open-session.sh parses" "bash -n \"$here/plugins/peasant/scripts/open-session.sh\""
check "hooks.json is valid JSON" "python3 -c 'import json;json.load(open(\"$here/plugins/peasant/hooks/hooks.json\"))'"
check "hooks.json targets the peasant command" "grep -q 'UserPromptExpansion' \"$here/plugins/peasant/hooks/hooks.json\" && grep -q 'peasant' \"$here/plugins/peasant/hooks/hooks.json\""
check "hooks.json calls the bundled script in hook mode" "grep -q 'open-session.sh --hook' \"$here/plugins/peasant/hooks/hooks.json\""
check "plain mode: missing peasant exits 0 with an ERROR line" \
  "env PATH=/usr/bin:/bin \"$here/plugins/peasant/scripts/open-session.sh\" test-session 2>&1 | grep -q '^ERROR:'"
check "hook mode: emits valid JSON with continue:false" \
  "printf '{\"session_id\":\"test-session\"}' | env PATH=/usr/bin:/bin \"$here/plugins/peasant/scripts/open-session.sh\" --hook | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"continue\"] is False and \"stopReason\" in d'"
check "hook mode: stopReason carries the ERROR" \
  "printf '{\"session_id\":\"test-session\"}' | env PATH=/usr/bin:/bin \"$here/plugins/peasant/scripts/open-session.sh\" --hook | grep -q 'ERROR:'"
check "hook mode: exits 0 (no blocking error)" \
  "printf '{\"session_id\":\"test-session\"}' | env PATH=/usr/bin:/bin \"$here/plugins/peasant/scripts/open-session.sh\" --hook >/dev/null 2>&1; [ \$? -eq 0 ]"

if command -v claude >/dev/null 2>&1; then
  check "claude plugin validate passes" "(cd \"$here\" && claude plugin validate .)"
else
  echo "skip: claude CLI not on PATH (cannot run 'claude plugin validate')"
fi

if [ "$fail" -eq 0 ]; then echo "ALL OK"; else echo "SMOKE FAILED"; fi
exit "$fail"
