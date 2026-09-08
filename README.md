# peasant-plugins

A Claude Code plugin marketplace for [peasant](https://github.com/peasant-labs/peasant).

## Plugins

### `peasant` — `/peasant`

Records the CURRENT Claude Code session into your local peasant store, starts the
peasant web dashboard if it is not already running, and opens THIS session's
transcript in your browser.

What it does when you type `/peasant`:

1. Finds this session's id.
2. If the session is not stored yet, asks before recording it; if it is already
   stored, refreshes it. It records ONLY this session, never the whole project.
3. Starts `peasant web` in the background if it is not already running.
4. Opens this session's transcript and prints the link.

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
- Session discovery uses the most recently written transcript for the current
  directory; it targets Claude Code sessions.
