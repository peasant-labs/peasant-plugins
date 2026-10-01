"""Reject executable interpolation of Claude's raw skill arguments."""
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()
fences = re.findall(r"```[^\n]*\n(.*?)```", text, re.S)
assert all("ARGUMENTS" not in fence for fence in fences)
assert "```!" not in text
