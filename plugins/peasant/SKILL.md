---
name: peasant
description: Harvest THIS Claude Code session into peasant and open its transcript in the local web dashboard.
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/open-session.sh *)
---

# /peasant — record and open this session

Record the CURRENT Claude Code session into your local peasant store, make sure
`peasant web` is running, and open THIS session's transcript in the dashboard.
`peasant open` does all of it; the bundled script only finds this session's id
and runs that command.

Prerequisite: the `peasant` binary must be installed and on your PATH
(https://github.com/peasant-labs/peasant), in a release that has the
`peasant open` command. This plugin does not install it.

Scope: this records ONLY the session that ran `/peasant`. It never harvests the
whole project.

## Normal path

The `UserPromptExpansion` hook in `hooks/hooks.json` handles `/peasant` before
this skill ever expands, so Claude is not invoked and no tokens are spent. You
are seeing this message because that hook did NOT run (for example, hooks are
disabled by policy). The injected script below already ran in its place; relay its output.

## Run (fallback only)

```!
${CLAUDE_PLUGIN_ROOT}/scripts/open-session.sh ${CLAUDE_SESSION_ID} 2>&1
```

## Relay

- Print the lines above for the user exactly as they are. Do nothing else.
  There are at most two: the result and the transcript address, or one line
  that says what failed and how to fix it.

Do not harvest, start the dashboard, or open anything yourself — `peasant open`
already did the whole flow and opened the browser.
