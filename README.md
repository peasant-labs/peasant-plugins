# peasant-plugins

A Claude Code plugin marketplace for [peasant](https://github.com/peasant-labs/peasant).

## Plugins

### `peasant` — `/peasant`

Records the CURRENT Claude Code session into your local peasant store, starts the
peasant web dashboard if it is not already running, and opens THIS session's
transcript in your browser.

What it does when you type `/peasant`:

1. Takes this session's id from Claude Code.
2. Runs `peasant open --session <id>`. That command records this session,
   starts the dashboard if it is not already running, and opens this
   session's transcript in your browser. It records ONLY this session, never
   the whole project.
3. Shows at most two lines: the result, for example
   `peasant: opened "<title>" · not published`, then the address of the
   transcript in the dashboard. If a step fails, it shows one line instead,
   which names the step, the reason, and the command that fixes it.
   `peasant open --help` describes the output.

The plugin's bundled script (`plugins/peasant/scripts/open-session.sh`) is a
thin shim over `peasant open`: it finds the session id and passes the
command's output on. A `UserPromptExpansion` hook (`plugins/peasant/hooks/hooks.json`)
runs it in hook mode, where `peasant open --hook` answers with a `stopReason`
that stops the command expansion. Claude never processes the prompt, so
`/peasant` costs no tokens and the agent does not reply. The two lines appear
as a normal user-facing note.

If hooks are disabled by policy, the skill body runs the same script as a
fallback, and that path does spend a turn.

## Prerequisite

You must have the `peasant` binary installed and on your `PATH`, in a release
that has the `peasant open` command. This plugin does not install or bundle it.
See https://github.com/peasant-labs/peasant. With an older peasant, `/peasant`
prints one line that asks you to run `peasant upgrade`, or
`peasant upgrade --prerelease` if that finds no newer release. A Homebrew
install gets stable releases only, so it gets `peasant open` with the first
stable release that has it.

## Install

```
/plugin marketplace add peasant-labs/peasant-plugins
/plugin install peasant@peasant-plugins
```

Then type `/peasant` in any session.

## Scope and limitations (MVP)

- Records only the session that ran `/peasant`.
- Uses peasant's default dashboard port: the plugin passes no `--port`.
- Takes the session id from the hook input, or from Claude Code's
  `${CLAUDE_SESSION_ID}` on the fallback path; when neither is available it falls
  back to the most recently written transcript for the current directory. It
  targets Claude Code sessions.
- Because the hook stops the command processing, the result renders as a
  user-facing note carrying the two lines, not as an assistant message.
