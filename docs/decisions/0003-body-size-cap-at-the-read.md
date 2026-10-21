# 3. The body size cap is enforced at the read, not after

## Status

Accepted (Phase 2).

## Context

`Relay.Event`'s changeset already rejects a body over 256 KB — but a
changeset validation runs only after the entire body has already been
read into memory and handed to `Repo.insert/1`. For a tool whose whole
job is accepting arbitrary POST requests from the internet, that's the
wrong place to enforce a limit: a large, deliberately oversized payload
would still be fully buffered before being rejected, which is exactly
the resource-exhaustion risk a size limit exists to prevent.

## Decision

The same 256 KB constant (`Event.max_body_bytes/0`) is passed as the
`:length` option both to `Plug.Parsers` (for the common case, where a
configured parser like JSON reads the body) and to
`ReceiveController`'s own fallback `Plug.Conn.read_body/2` call (for a
content type no parser claims). In both cases, the read itself stops at
the limit: `Plug.Parsers` raises `Plug.Parsers.RequestTooLargeError`,
which Plug's adapter turns into an HTTP 413 automatically, and the
controller's own fallback returns `{:more, _, conn}`, mapped to the same
413 response. Either way, a body over the limit is never fully read,
and `Relay.record_event/2` is never even called.

## Alternatives considered

- **Rely on the changeset validation alone.** Already covered above:
  it only protects the database, not memory, and only after the full
  cost of reading an oversized body has already been paid.
- **A separate, hand-written streaming length check before handing off
  to `Plug.Parsers`.** Would duplicate behavior `Plug.Parsers`' own
  `:length` option already provides correctly, for the common
  (JSON) case — the custom code is only needed for the fallback path
  `Plug.Parsers` doesn't touch at all.

## Consequences

- An oversized payload costs the server only as much read time as it
  takes to hit the cap, not the time to read, decode, and then discard
  the whole thing.
- The changeset's own `validate_body_size/1` check is now mostly a
  second line of defense — redundant for requests that come through
  `ReceiveController`, but it still matters for any future code path
  that constructs an `Event` changeset directly (a test, a console
  session, a future import tool) without going through the controller's
  read-time cap at all.
