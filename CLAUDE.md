# Hookline — conventions

Webhook relay and debugger: capture inbound webhooks, inspect and replay
them, and forward them to a real destination with retries. Portfolio-
quality Elixir/Phoenix app; hold every change to these rules. Keep it
well-designed and finished, and add complexity only where this app
actually needs it, not speculatively.

## Architecture

- **Business logic lives in contexts** (`Hookline.Accounts`,
  `Hookline.Relay`, ...). Contexts are the only modules that touch `Repo`.
- **The web layer (controllers, LiveViews, plugs) never calls `Repo`
  directly** and never builds `Ecto.Query`s itself. It calls context
  functions.
- Oban workers call context functions too; they don't reach into `Repo`
  directly.
- External HTTP calls (forwarding to destinations) go through a `@behaviour`
  with a real implementation and a Mox-based test double. Nothing in `lib/`
  hardcodes a concrete HTTP client.

## Function contracts

- Every public context function has `@doc` and `@spec`.
- Functions that can fail return `{:ok, result}` or `{:error, reason}`,
  never raising for expected failure modes (validation errors, not-found,
  a destination returning an error). Reserve `!`-suffixed functions for the
  conventional Phoenix "raise if truly not there" cases.
- No silently swallowed errors. A `rescue` or `catch` that discards the
  error without logging or returning it is a bug.

## Testing

- Every feature ships with tests alongside it in the same phase or commit,
  not "add tests later."
- No test ever makes a real network call. Destinations are always the
  Mox double.
- Prefer testing context functions directly over testing through LiveView
  where the logic under test isn't actually about the UI.

## Style

- Run `mix format` before committing.
- `mix credo --strict` and `mix dialyzer` must be clean before a phase is
  considered done.
