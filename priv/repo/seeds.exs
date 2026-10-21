# Populates a demo user with two endpoints, a destination each, and a
# handful of captured events with delivery history, so a fresh clone or
# a public demo deployment has something to look at immediately.
#
#     mix run priv/repo/seeds.exs
#
# Events are stored through Relay.record_event/2, the same function the
# real receiving URL uses, so their shape is real. Delivery attempts are
# written directly through Relay.record_attempt/3 rather than actually
# run through DeliveryWorker/Oban — seeding should never make a real
# network call to whatever destination URL ends up here, so these are
# plausible sample results, not a real delivery history.
#
# Safe to run more than once: it does nothing if the demo user already
# has an endpoint.

alias Hookline.Accounts
alias Hookline.Accounts.User
alias Hookline.Relay
alias Hookline.Repo

demo_email = "demo@hookline.dev"
demo_password = "demo-password-please-change"

user =
  case Repo.get_by(User, email: demo_email) do
    nil ->
      {:ok, user} = Accounts.register_user(%{email: demo_email, password: demo_password})
      user

    existing ->
      existing
  end

if Relay.list_endpoints(user) == [] do
  {:ok, stripe} = Relay.create_endpoint(user, %{name: "Stripe webhooks"})

  {:ok, _stripe_dest} =
    Relay.create_destination(user, stripe, %{url: "https://example.com/hooks/stripe"})

  {:ok, github} = Relay.create_endpoint(user, %{name: "GitHub webhooks"})

  {:ok, _github_dest} =
    Relay.create_destination(user, github, %{url: "https://example.com/hooks/github"})

  now = DateTime.utc_now()

  stripe_events = [
    {~s({"id":"evt_1","type":"payment_intent.succeeded","amount":4999}),
     %{"content-type" => "application/json", "stripe-signature" => "t=1,v1=abc123"}, :succeeded,
     200, nil},
    {~s({"id":"evt_2","type":"payment_intent.payment_failed","amount":1200}),
     %{"content-type" => "application/json", "stripe-signature" => "t=2,v1=def456"}, :succeeded,
     200, nil},
    {~s({"id":"evt_3","type":"customer.subscription.deleted"}),
     %{"content-type" => "application/json", "stripe-signature" => "t=3,v1=ghi789"}, :failed, 503,
     nil}
  ]

  github_events = [
    {~s({"action":"opened","pull_request":{"number":42,"title":"Add retry logic"}}),
     %{"content-type" => "application/json", "x-github-event" => "pull_request"}, :succeeded, 200,
     nil},
    {~s({"action":"completed","workflow_run":{"conclusion":"success"}}),
     %{"content-type" => "application/json", "x-github-event" => "workflow_run"}, :failed, nil,
     "connection timeout"}
  ]

  seed_events = fn endpoint, events ->
    events
    |> Enum.with_index()
    |> Enum.each(fn {{body, headers, status, response_code, error}, index} ->
      received_at = DateTime.add(now, -index * 3600, :second)

      {:ok, event} =
        Relay.record_event(endpoint, %{
          method: "POST",
          headers: headers,
          body: body,
          received_at: received_at
        })

      [destination] = Relay.list_destinations(endpoint)

      {:ok, _attempt} =
        Relay.record_attempt(event, destination, %{
          attempt_number: 1,
          status: status,
          response_code: response_code,
          error: error,
          attempted_at: DateTime.add(received_at, 1, :second)
        })
    end)
  end

  seed_events.(stripe, stripe_events)
  seed_events.(github, github_events)
end

IO.puts("""

Seeded demo user:
  email:    #{demo_email}
  password: #{demo_password}
""")
