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

if command -v claude >/dev/null 2>&1; then
  check "claude plugin validate passes" "(cd \"$here\" && claude plugin validate .)"
else
  echo "skip: claude CLI not on PATH (cannot run 'claude plugin validate')"
fi

if [ "$fail" -eq 0 ]; then echo "ALL OK"; else echo "SMOKE FAILED"; fi
exit "$fail"
