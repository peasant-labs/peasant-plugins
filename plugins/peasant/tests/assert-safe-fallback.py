"""Reject executable interpolation of Claude's raw skill arguments."""
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()
fences = re.findall(r"```[^\n]*\n(.*?)```", text, re.S)
assert all("ARGUMENTS" not in fence for fence in fences)
assert "```!" not in text

# The hooks-disabled fallback must keep the exact fixed commands the script
# understands; a reflow that drops one silently breaks the fallback.
required = [
    '"${CLAUDE_PLUGIN_ROOT}/scripts/open-session.sh" --args auto "${CLAUDE_SESSION_ID}" 2>&1',
    '"${CLAUDE_PLUGIN_ROOT}/scripts/open-session.sh" "${CLAUDE_SESSION_ID}" 2>&1',
]
for command in required:
    assert command in text, f"the skill fallback omits the fixed command: {command}"
