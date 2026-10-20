defmodule HooklineWeb.EndpointLive.EventTest do
  use HooklineWeb.ConnCase, async: true
  use Oban.Testing, repo: Hookline.Repo

  import Phoenix.LiveViewTest
  import Mox
  import Hookline.RelayFixtures

  alias Hookline.Relay
  alias Hookline.Relay.DeliveryWorker

  setup :register_and_log_in_user
  setup :verify_on_exit!

  describe "Show" do
    test "renders headers, body, and an empty attempts state", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)

      event =
        event_fixture(endpoint, %{
          headers: %{"x-signature" => "sig123"},
          body: ~s({"ok": true})
        })

      {:ok, _view, html} = live(conn, ~p"/endpoints/#{endpoint}/events/#{event}")

      assert html =~ "x-signature"
      assert html =~ "sig123"
      assert html =~ "{&quot;ok&quot;: true}"
      assert html =~ "No delivery attempts yet"
    end

    test "lists delivery attempts already made", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)
      destination = destination_fixture(user, endpoint)
      event = event_fixture(endpoint)

      {:ok, _attempt} =
        Relay.record_attempt(event, destination, %{
          attempt_number: 1,
          status: :succeeded,
          response_code: 200,
          attempted_at: DateTime.utc_now()
        })

      {:ok, _view, html} = live(conn, ~p"/endpoints/#{endpoint}/events/#{event}")

      assert html =~ "succeeded"
      assert html =~ "200"
    end

    test "a new delivery attempt appears live, with no reload", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)
      destination = destination_fixture(user, endpoint)
      event = event_fixture(endpoint)

      {:ok, view, _html} = live(conn, ~p"/endpoints/#{endpoint}/events/#{event}")
      assert render(view) =~ "No delivery attempts yet"

      {:ok, _attempt} =
        Relay.record_attempt(event, destination, %{
          attempt_number: 1,
          status: :failed,
          response_code: 503,
          attempted_at: DateTime.utc_now()
        })

      html = render(view)
      refute html =~ "No delivery attempts yet"
      assert html =~ "failed"
      assert html =~ "503"
    end

    test "the replay button enqueues a fresh delivery for every active destination", %{
      conn: conn,
      user: user
    } do
      endpoint = endpoint_fixture(user)
      destination = destination_fixture(user, endpoint)
      event = event_fixture(endpoint)

      {:ok, view, _html} = live(conn, ~p"/endpoints/#{endpoint}/events/#{event}")

      view |> element("button", "Replay") |> render_click()

      assert render(view) =~ "Replaying this event"

      assert_enqueued(
        worker: DeliveryWorker,
        args: %{event_id: event.id, destination_id: destination.id}
      )
    end

    test "replaying actually delivers, via the real worker", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)
      _destination = destination_fixture(user, endpoint)
      event = event_fixture(endpoint)

      {:ok, view, _html} = live(conn, ~p"/endpoints/#{endpoint}/events/#{event}")

      expect(Hookline.Relay.HttpClientMock, :post, fn _url, _body, _headers -> {:ok, 200} end)

      view |> element("button", "Replay") |> render_click()

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :deliveries)

      assert render(view) =~ "succeeded"
    end

    test "redirects to the endpoints list for an event on another user's endpoint", %{conn: conn} do
      other = Hookline.AccountsFixtures.user_fixture()
      theirs = endpoint_fixture(other)
      event = event_fixture(theirs)

      assert {:error, {:live_redirect, %{to: "/endpoints"}}} =
               live(conn, ~p"/endpoints/#{theirs}/events/#{event}")
    end

    test "redirects for a nonexistent event on an owned endpoint", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)

      assert {:error, {:live_redirect, %{to: "/endpoints"}}} =
               live(conn, ~p"/endpoints/#{endpoint}/events/999999")
    end
  end
end
