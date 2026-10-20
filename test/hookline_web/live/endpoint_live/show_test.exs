defmodule HooklineWeb.EndpointLive.ShowTest do
  use HooklineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hookline.RelayFixtures

  alias Hookline.Relay

  setup :register_and_log_in_user

  describe "Show" do
    test "renders the receiving URL and an empty events state", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user, %{name: "Stripe prod"})

      {:ok, _view, html} = live(conn, ~p"/endpoints/#{endpoint}")

      assert html =~ "Stripe prod"
      assert html =~ endpoint.token
      assert html =~ "No events yet"
      assert html =~ "No destinations yet"
    end

    test "lists captured events", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)
      _event = event_fixture(endpoint, %{method: "POST"})

      {:ok, _view, html} = live(conn, ~p"/endpoints/#{endpoint}")

      assert html =~ "POST"
    end

    test "adds a destination", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/endpoints/#{endpoint}")

      view
      |> form("#destination-form", destination: %{url: "https://example.com/webhooks"})
      |> render_submit()

      assert render(view) =~ "https://example.com/webhooks"
      assert [_destination] = Relay.list_destinations(endpoint)
    end

    test "rejects a non-http destination URL", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/endpoints/#{endpoint}")

      html =
        view
        |> form("#destination-form", destination: %{url: "ftp://example.com"})
        |> render_submit()

      assert html =~ "must be an http or https URL"
    end

    test "a newly captured event appears live, with no reload", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/endpoints/#{endpoint}")

      assert render(view) =~ "No events yet"

      {:ok, _event} =
        Relay.record_event(endpoint, %{
          method: "POST",
          headers: %{},
          body: "live-updated",
          received_at: DateTime.utc_now()
        })

      html = render(view)
      refute html =~ "No events yet"
      assert html =~ "POST"
    end

    test "redirects to the endpoints list for another user's endpoint", %{conn: conn} do
      other = Hookline.AccountsFixtures.user_fixture()
      theirs = endpoint_fixture(other)

      assert {:error, {:live_redirect, %{to: "/endpoints"}}} =
               live(conn, ~p"/endpoints/#{theirs}")
    end

    test "redirects for a nonexistent endpoint", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/endpoints"}}} = live(conn, ~p"/endpoints/999999")
    end
  end
end
