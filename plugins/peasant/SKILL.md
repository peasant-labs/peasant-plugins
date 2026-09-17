---
name: peasant
description: Harvest THIS Claude Code session into peasant and open its transcript in the local web dashboard.
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/open-session.sh *)
---

# /peasant — record and open this session

Record the CURRENT Claude Code session into your local peasant store, make sure
`peasant web` is running, and open THIS session's transcript in the dashboard.

Prerequisite: the `peasant` binary must be installed and on your PATH
(https://github.com/peasant-labs/peasant). This plugin does not install it.

Scope: this records ONLY the session that ran `/peasant`. It never harvests the
whole project.

## Normal path

The `UserPromptExpansion` hook in `hooks/hooks.json` handles `/peasant` before
this skill ever expands, so Claude is not invoked and no tokens are spent. You
are seeing this message because that hook did NOT run (for example, hooks are
disabled by policy). Run the script below to do the same work yourself.

## Run (fallback only)

```!
${CLAUDE_PLUGIN_ROOT}/scripts/open-session.sh ${CLAUDE_SESSION_ID} 2>&1
```

## Relay

- Print the `URL:` line above for the user. Do nothing else.
- If the output begins with `ERROR:`, relay that message instead and stop.

Do not harvest, start the dashboard, or open anything yourself — the script
already did the whole flow.
