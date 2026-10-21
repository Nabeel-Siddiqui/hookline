# 2. Retries are Oban's own mechanism, one job per destination

## Status

Accepted (Phase 3).

## Context

Delivering a captured event means POSTing it to every destination
configured on its endpoint. A destination can be slow, briefly down, or
permanently broken, and a failure on one destination should never
delay or block delivery to another. Retrying a failed delivery needs a
backoff policy — retrying instantly in a tight loop just hammers a
struggling destination harder.

## Decision

`Relay.enqueue_deliveries/1` inserts one `DeliveryWorker` Oban job per
active destination on the event's endpoint — independent jobs with
independent lifecycles, not one job iterating over every destination.
`DeliveryWorker` is configured with `max_attempts: 5` and a `backoff/1`
callback that doubles each time (1s, 2s, 4s, 8s, 16s). A 2xx response is
the only success; anything else (a non-2xx status, a timeout, a
connection refusal) is recorded as a failed `DeliveryAttempt` and
returned as `{:error, _}`, which is what tells Oban to schedule the next
attempt using that `backoff/1`. After the 5th failure, Oban discards the
job — the `DeliveryAttempt` rows already give full history, so there's
nothing more for the worker itself to do.

## Alternatives considered

- **One job per event, looping over its destinations internally.**
  Simpler to enqueue, but couples every destination's delivery outcome
  together: a slow or failing destination would hold up the whole job,
  including destinations that would have succeeded immediately. It would
  also mean hand-rolling per-destination retry state inside a single
  job's args, duplicating what Oban's own `attempt`/`max_attempts`
  already track.
- **A hand-rolled retry loop with `Process.sleep/1` inside the worker.**
  Blocks the worker process for the entire backoff window, and loses all
  progress (and the DB record of in-progress retries) if the node
  restarts mid-wait. Oban's own retry scheduling persists the job in
  Postgres between attempts, so a restart loses nothing.

## Consequences

- Destinations on the same event genuinely don't affect each other's
  delivery timing or outcome.
- Backoff timing is exactly the sequence stated in this app's README,
  not Oban's own default (which also backs off exponentially, but with
  different constants) — worth noting for anyone reading the retry
  behavior expecting Oban's stock timing.
- A destination that's down for longer than the roughly 31-second span
  of 5 attempts (1+2+4+8+16) is given up on automatically. There's no
  automatic re-delivery after that; replay is manual, from the
  dashboard.
