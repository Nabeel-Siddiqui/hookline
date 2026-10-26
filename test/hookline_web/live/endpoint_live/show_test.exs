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

    test "shows the signing secret and no verification by default", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/endpoints/#{endpoint}")

      assert html =~ endpoint.signing_secret
      assert html =~ "Not verifying"
    end

    test "setting a signature header turns verification on", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/endpoints/#{endpoint}")

      view
      |> form("#signature-form", endpoint: %{signature_header: "x-hub-signature-256"})
      |> render_submit()

      html = render(view)
      assert html =~ "Verifying"
      assert html =~ "x-hub-signature-256"
    end

    test "regenerating the secret replaces it", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/endpoints/#{endpoint}")
      old_secret = endpoint.signing_secret

      view |> element("button", "Regenerate") |> render_click()

      html = render(view)
      refute html =~ old_secret
    end

    test "filtering by method hides events that don't match", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)
      _post = event_fixture(endpoint, %{method: "POST"})
      _put = event_fixture(endpoint, %{method: "PUT"})

      {:ok, view, html} = live(conn, ~p"/endpoints/#{endpoint}")
      assert count_occurrences(html, "View") == 2

      html =
        view
        |> form("#event-filters", filters: %{method: "POST"})
        |> render_change()

      assert count_occurrences(html, "View") == 1
      refute html =~ "No events match these filters."
    end

    test "a live-captured event respects the active filter", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/endpoints/#{endpoint}")

      view
      |> form("#event-filters", filters: %{method: "PUT"})
      |> render_change()

      {:ok, _event} =
        Relay.record_event(endpoint, %{
          method: "POST",
          headers: %{},
          body: "won't match the filter",
          received_at: DateTime.utc_now()
        })

      assert render(view) =~ "No events match these filters."
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

  defp count_occurrences(haystack, needle) do
    haystack |> String.split(needle) |> length() |> Kernel.-(1)
  end
end
