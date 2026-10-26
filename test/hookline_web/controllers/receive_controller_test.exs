defmodule HooklineWeb.ReceiveControllerTest do
  use HooklineWeb.ConnCase, async: true
  use Oban.Testing, repo: Hookline.Repo

  import Hookline.AccountsFixtures
  import Hookline.RelayFixtures

  alias Hookline.Relay
  alias Hookline.Relay.{DeliveryWorker, Event}

  defp hex_hmac(secret, body) do
    :hmac
    |> :crypto.mac(:sha256, secret, body)
    |> Base.encode16(case: :lower)
  end

  describe "POST /in/:token" do
    test "captures a JSON webhook exactly as sent and returns 200", %{conn: conn} do
      endpoint = endpoint_fixture()
      body = ~s({"id": "evt_123", "amount": 4999})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-signature", "abc123")
        |> post(~p"/in/#{endpoint.token}", body)

      assert conn.status == 200

      assert [event] = Relay.list_events(endpoint)
      assert event.method == "POST"
      assert event.body == body
      assert event.headers["x-signature"] == "abc123"
      assert event.headers["content-type"] == "application/json"
    end

    test "captures a non-JSON body too, via the fallback raw read", %{conn: conn} do
      endpoint = endpoint_fixture()
      body = "plain text payload"

      conn =
        conn
        |> put_req_header("content-type", "text/plain")
        |> post(~p"/in/#{endpoint.token}", body)

      assert conn.status == 200
      assert [event] = Relay.list_events(endpoint)
      assert event.body == body
    end

    test "returns 404 for an unknown token, without touching the database", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/in/no-such-token", ~s({}))

      assert conn.status == 404
    end

    test "rejects a body over the size limit with 413, and stores nothing", %{conn: conn} do
      endpoint = endpoint_fixture()
      oversized = String.duplicate("a", Event.max_body_bytes() + 1)

      assert_error_sent 413, fn ->
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/in/#{endpoint.token}", oversized)
      end

      assert Relay.list_events(endpoint) == []
    end

    test "enqueues a delivery for every active destination once the event is captured", %{
      conn: conn
    } do
      user = user_fixture()
      endpoint = endpoint_fixture(user)
      destination = destination_fixture(user, endpoint)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/in/#{endpoint.token}", ~s({"ok": true}))

      assert conn.status == 200
      assert [event] = Relay.list_events(endpoint)

      assert_enqueued(
        worker: DeliveryWorker,
        args: %{event_id: event.id, destination_id: destination.id}
      )
    end

    test "accepts a request with a valid signature, once a header is configured", %{conn: conn} do
      user = user_fixture()
      endpoint = endpoint_fixture(user)

      {:ok, endpoint} =
        Relay.update_endpoint_signature(user, endpoint, %{signature_header: "x-sig"})

      body = ~s({"ok": true})
      signature = "sha256=" <> hex_hmac(endpoint.signing_secret, body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-sig", signature)
        |> post(~p"/in/#{endpoint.token}", body)

      assert conn.status == 200
      assert [_event] = Relay.list_events(endpoint)
    end

    test "rejects a request with a missing signature, once a header is configured", %{
      conn: conn
    } do
      user = user_fixture()
      endpoint = endpoint_fixture(user)

      {:ok, endpoint} =
        Relay.update_endpoint_signature(user, endpoint, %{signature_header: "x-sig"})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/in/#{endpoint.token}", ~s({"ok": true}))

      assert conn.status == 401
      assert Relay.list_events(endpoint) == []
    end

    test "rejects a request with a wrong signature, and stores nothing", %{conn: conn} do
      user = user_fixture()
      endpoint = endpoint_fixture(user)

      {:ok, endpoint} =
        Relay.update_endpoint_signature(user, endpoint, %{signature_header: "x-sig"})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-sig", "sha256=deadbeef")
        |> post(~p"/in/#{endpoint.token}", ~s({"ok": true}))

      assert conn.status == 401
      assert Relay.list_events(endpoint) == []
    end
  end
end
