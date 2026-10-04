defmodule Hookline.RelayTest do
  use Hookline.DataCase, async: true

  import Hookline.AccountsFixtures
  import Hookline.RelayFixtures

  alias Hookline.Relay
  alias Hookline.Relay.{Destination, Event}

  describe "create_endpoint/2" do
    test "creates an endpoint with a generated public token" do
      user = user_fixture()

      assert {:ok, endpoint} = Relay.create_endpoint(user, %{name: "Stripe prod"})
      assert endpoint.name == "Stripe prod"
      assert endpoint.user_id == user.id
      assert is_binary(endpoint.token)
      assert byte_size(endpoint.token) >= 20
    end

    test "gives each endpoint a different token" do
      user = user_fixture()
      a = endpoint_fixture(user)
      b = endpoint_fixture(user)

      refute a.token == b.token
    end

    test "requires a name" do
      user = user_fixture()

      assert {:error, changeset} = Relay.create_endpoint(user, %{})
      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "get_endpoint/2" do
    test "returns the endpoint for its owner" do
      user = user_fixture()
      endpoint = endpoint_fixture(user)

      assert {:ok, ^endpoint} = Relay.get_endpoint(user, endpoint.id)
    end

    test "returns :not_found for another user's endpoint" do
      owner = user_fixture()
      other = user_fixture()
      endpoint = endpoint_fixture(owner)

      assert {:error, :not_found} = Relay.get_endpoint(other, endpoint.id)
    end

    test "returns :not_found for a malformed id instead of raising" do
      user = user_fixture()

      assert {:error, :not_found} = Relay.get_endpoint(user, "not-an-id")
    end
  end

  describe "get_endpoint_by_token/1" do
    test "finds the endpoint by its token, with no user needed" do
      endpoint = endpoint_fixture()

      assert {:ok, found} = Relay.get_endpoint_by_token(endpoint.token)
      assert found.id == endpoint.id
    end

    test "returns :not_found for an unknown token" do
      assert {:error, :not_found} = Relay.get_endpoint_by_token("no-such-token")
    end
  end

  describe "list_endpoints/1" do
    test "lists only the user's own endpoints" do
      user = user_fixture()
      other = user_fixture()
      mine = endpoint_fixture(user, %{name: "Mine"})
      _theirs = endpoint_fixture(other, %{name: "Theirs"})

      assert Relay.list_endpoints(user) |> Enum.map(& &1.id) == [mine.id]
    end
  end

  describe "create_destination/3" do
    test "adds a destination to an owned endpoint" do
      user = user_fixture()
      endpoint = endpoint_fixture(user)

      assert {:ok, %Destination{} = destination} =
               Relay.create_destination(user, endpoint, %{url: "https://example.com/hook"})

      assert destination.endpoint_id == endpoint.id
      assert destination.active
    end

    test "rejects a URL that isn't http or https" do
      user = user_fixture()
      endpoint = endpoint_fixture(user)

      assert {:error, changeset} =
               Relay.create_destination(user, endpoint, %{url: "ftp://example.com/hook"})

      assert "must be an http or https URL" in errors_on(changeset).url
    end

    test "refuses to add a destination to another user's endpoint" do
      owner = user_fixture()
      other = user_fixture()
      endpoint = endpoint_fixture(owner)

      assert {:error, :not_found} =
               Relay.create_destination(other, endpoint, %{url: "https://example.com/hook"})
    end
  end

  describe "record_event/2" do
    test "stores a captured request on the endpoint" do
      endpoint = endpoint_fixture()

      assert {:ok, %Event{} = event} =
               Relay.record_event(endpoint, %{
                 method: "POST",
                 body: "hello",
                 received_at: DateTime.utc_now()
               })

      assert event.endpoint_id == endpoint.id
      assert event.body == "hello"
    end

    test "accepts a body exactly at the size limit" do
      endpoint = endpoint_fixture()
      body = String.duplicate("a", Event.max_body_bytes())

      assert {:ok, _event} =
               Relay.record_event(endpoint, %{
                 method: "POST",
                 body: body,
                 received_at: DateTime.utc_now()
               })
    end

    test "rejects a body one byte over the size limit and stores nothing" do
      endpoint = endpoint_fixture()
      body = String.duplicate("a", Event.max_body_bytes() + 1)

      assert {:error, changeset} =
               Relay.record_event(endpoint, %{
                 method: "POST",
                 body: body,
                 received_at: DateTime.utc_now()
               })

      assert "must be at most #{Event.max_body_bytes()} bytes" in errors_on(changeset).body
      assert Relay.list_events(endpoint) == []
    end

    test "counts the limit in bytes, not characters" do
      endpoint = endpoint_fixture()
      # "é" is one character but two bytes in UTF-8.
      body = String.duplicate("é", div(Event.max_body_bytes(), 2) + 1)

      assert {:error, _changeset} =
               Relay.record_event(endpoint, %{
                 method: "POST",
                 body: body,
                 received_at: DateTime.utc_now()
               })
    end
  end

  describe "list_events/1" do
    test "lists the endpoint's events, newest first" do
      endpoint = endpoint_fixture()
      older = event_fixture(endpoint, %{received_at: ~U[2026-01-01 10:00:00Z]})
      newer = event_fixture(endpoint, %{received_at: ~U[2026-01-02 10:00:00Z]})

      assert Relay.list_events(endpoint) |> Enum.map(& &1.id) == [newer.id, older.id]
    end
  end

  describe "delivery attempts" do
    test "records attempts for an event and lists them in order" do
      user = user_fixture()
      endpoint = endpoint_fixture(user)
      destination = destination_fixture(user, endpoint)
      event = event_fixture(endpoint)
      now = DateTime.utc_now()

      {:ok, first} =
        Relay.record_attempt(event, destination, %{
          attempt_number: 1,
          status: :failed,
          response_code: 503,
          attempted_at: now
        })

      {:ok, second} =
        Relay.record_attempt(event, destination, %{
          attempt_number: 2,
          status: :succeeded,
          response_code: 200,
          attempted_at: DateTime.add(now, 2, :second)
        })

      assert Relay.list_attempts(event) |> Enum.map(& &1.id) == [first.id, second.id]
    end

    test "rejects an unknown status" do
      user = user_fixture()
      endpoint = endpoint_fixture(user)
      destination = destination_fixture(user, endpoint)
      event = event_fixture(endpoint)

      assert {:error, changeset} =
               Relay.record_attempt(event, destination, %{
                 attempt_number: 1,
                 status: :maybe,
                 attempted_at: DateTime.utc_now()
               })

      assert "is invalid" in errors_on(changeset).status
    end
  end
end
