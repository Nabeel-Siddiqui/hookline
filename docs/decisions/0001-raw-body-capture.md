# 1. The exact raw body is captured, not a re-serialized one

## Status

Accepted (Phase 2).

## Context

A webhook sender almost always posts `Content-Type: application/json`.
Phoenix's default `Plug.Parsers` pipeline matches that content type and
decodes the body into `conn.body_params` before the request ever reaches
a controller. That's the right behavior for a normal JSON API, but wrong
here: Hookline's whole value is capturing and replaying a webhook
exactly as it was sent, and a decoded-then-re-encoded JSON body is not
guaranteed to be byte-for-byte identical to what arrived (key order,
whitespace, and number formatting can all differ). A destination's
signature verification, computed over the original bytes, would then
fail on a replay even though the logical content is unchanged.

## Decision

`HooklineWeb.CacheBodyReader` is a custom `Plug.Parsers` `:body_reader`.
It wraps the standard `Plug.Conn.read_body/2`, stashes the raw bytes in
`conn.assigns[:raw_body]` as they're read, and then hands them on to
whichever parser (JSON, in the common case) consumes them normally.
`ReceiveController` reads `conn.assigns[:raw_body]` directly rather than
`conn.body_params`.

For a content type no configured parser claims, `Plug.Parsers` (with
`pass: ["*/*"]`) leaves the body completely unread — the body reader
never runs. `ReceiveController` falls back to reading it directly itself
in that case, with the same length cap (see
[ADR 3](0003-body-size-cap-at-the-read.md)).

## Alternatives considered

- **Decode the body and re-encode it for storage/replay.** Simpler, and
  wrong for the reason above — a re-encoded JSON body is not what the
  sender actually transmitted.
- **Skip `Plug.Parsers` entirely for the receiving route.** Possible via
  a separate pipeline, but it would mean reimplementing the parser's own
  length-capping and content-type handling from scratch for the common
  JSON case, for no benefit — the body reader hook is the mechanism
  `Plug.Parsers` already provides for exactly this.

## Consequences

- A replayed event sends precisely what was received the first time,
  so a destination's signature verification behaves identically on a
  replay as it did on the original delivery.
- Every request to the app — not just the receiving URL — now has its
  raw body additionally stashed in `conn.assigns` while being parsed.
  Harmless overhead at this app's scale; it's simply unused on every
  other route.
