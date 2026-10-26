# 4. Signature verification is one generic HMAC scheme, not per-provider

## Status

Accepted (signature verification feature).

## Context

Hookline forwards a sender's own signature header to its destinations
untouched (see [ADR 1](0001-raw-body-capture.md)), so a destination's
*own* verification already works on replay. What it didn't do was
verify anything on the way *in* — a forged request with the right URL
token was captured and forwarded exactly like a genuine one. Real
senders don't agree on one signature scheme, though: GitHub, Shopify,
and many others send `sha256=<hex HMAC of the raw body>`; Stripe folds
a timestamp into the signed payload (`t=<ts>,v1=<hex HMAC of
"{ts}.{body}">`) specifically to add replay protection within a time
window.

## Decision

Each endpoint gets one auto-generated `signing_secret` and an optional
`signature_header`. When the header is set, every inbound request must
carry a matching `sha256=<hex HMAC-SHA256 of the raw body>` (or a bare
hex digest) in that header, verified in constant time by
`Hookline.Relay.SignatureVerifier`, a pure function with no knowledge
of Hookline's data model. A mismatch is rejected with 401 before
`record_event/2` is ever called — a forged request is never stored,
not stored-then-flagged. When no header is configured, every request
is accepted, unchanged from before this feature existed.

Stripe's timestamped variant is explicitly not implemented. It's a
different signed payload, not just a different header name, and
supporting it well means deciding on a replay-window policy too —
scope for a second pass, not a reason to delay shipping the scheme
that already covers the common case.

## Alternatives considered

- **Detect the provider and use its exact scheme automatically.**
  Friendlier, but means hardcoding a growing list of provider formats
  into the app instead of one generic mechanism the user configures
  once per endpoint, matching whatever their sender's dashboard calls
  the signature it sends.
- **Store the secret hashed, like `Beacon`'s API tokens.** Doesn't
  work here: verifying an HMAC requires the actual secret to recompute
  it, not just something to compare a hash against. The secret is
  stored in plaintext in `endpoints.signing_secret`, the same
  trade-off most webhook relays make for a value the user has to be
  able to hand to their sender's dashboard anyway.

## Consequences

- An endpoint with no signature header configured behaves exactly as
  it did before — nothing about existing endpoints changes until
  their owner opts in.
- A compromised database row exposes a usable signing secret, since
  it isn't hashed. The "Regenerate" button is the mitigation: a leaked
  secret is one click from being worthless, the same way an endpoint's
  token already was.
- Stripe senders (and anyone else with a non-GitHub-style scheme)
  don't get inbound verification yet. The README's "what I'd do next"
  calls this out explicitly rather than claiming broader support than
  the app actually has.
