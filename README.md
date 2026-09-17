# peasant-plugins

A Claude Code plugin marketplace for [peasant](https://github.com/peasant-labs/peasant).

## Plugins

### `peasant` — `/peasant`

Records the CURRENT Claude Code session into your local peasant store, starts the
peasant web dashboard if it is not already running, and opens THIS session's
transcript in your browser.

What it does when you type `/peasant`:

1. Takes this session's id from Claude Code.
2. Records this session (refreshing it if already stored) and shows a short
   progress line. It records ONLY this session, never the whole project.
3. Starts `peasant web` in the background if it is not already running.
4. Opens this session's transcript and prints the link.

The whole flow is one bundled script
(`plugins/peasant/scripts/open-session.sh`), and a `UserPromptExpansion` hook
(`plugins/peasant/hooks/hooks.json`) runs it and blocks the command expansion.
Claude is never invoked, so `/peasant` costs no tokens and takes a couple of
seconds. The hook reports progress and the URL to you directly.

If hooks are disabled by policy, the skill body runs the same script as a
fallback, and that path does spend a turn.

## Prerequisite

You must have the `peasant` binary installed and on your `PATH`. This plugin does
not install or bundle it. See https://github.com/peasant-labs/peasant.

## Install

```
/plugin marketplace add peasant-labs/peasant-plugins
/plugin install peasant@peasant-plugins
```

Then type `/peasant` in any session.

## Scope and limitations (MVP)

- Records only the session that ran `/peasant`.
- Assumes the default dashboard port `8690`.
- Takes the session id from the hook input, or from Claude Code's
  `${CLAUDE_SESSION_ID}` on the fallback path; when neither is available it falls
  back to the most recently written transcript for the current directory. It
  targets Claude Code sessions.
- Because the hook blocks the command, the result renders as a block notice
  showing the progress line and URL, not as an assistant message.
