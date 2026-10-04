defmodule Hookline.RelayFixtures do
  @moduledoc """
  Test helpers that build relay records through the `Hookline.Relay`
  context.
  """

  alias Hookline.Relay

  import Hookline.AccountsFixtures

  def endpoint_fixture(user \\ nil, attrs \\ %{}) do
    user = user || user_fixture()
    {:ok, endpoint} = Relay.create_endpoint(user, Enum.into(attrs, %{name: "Stripe prod"}))
    endpoint
  end

  def destination_fixture(user, endpoint, attrs \\ %{}) do
    {:ok, destination} =
      Relay.create_destination(
        user,
        endpoint,
        Enum.into(attrs, %{url: "https://example.com/hooks"})
      )

    destination
  end

  def event_fixture(endpoint, attrs \\ %{}) do
    {:ok, event} =
      Relay.record_event(
        endpoint,
        Enum.into(attrs, %{
          method: "POST",
          headers: %{"content-type" => "application/json"},
          body: ~s({"ok": true}),
          received_at: DateTime.utc_now()
        })
      )

    event
  end
end
