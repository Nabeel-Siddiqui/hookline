defmodule HooklineWeb.EndpointLive.IndexTest do
  use HooklineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hookline.RelayFixtures

  setup :register_and_log_in_user

  describe "Index" do
    test "lists the user's endpoints with their receiving URL", %{conn: conn, user: user} do
      endpoint = endpoint_fixture(user, %{name: "Stripe prod"})

      {:ok, _view, html} = live(conn, ~p"/endpoints")

      assert html =~ "Stripe prod"
      assert html =~ endpoint.token
    end

    test "shows an empty state with no endpoints", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/endpoints")

      assert html =~ "No endpoints yet"
    end

    test "doesn't show another user's endpoints", %{conn: conn} do
      other = Hookline.AccountsFixtures.user_fixture()
      _theirs = endpoint_fixture(other, %{name: "Not mine"})

      {:ok, _view, html} = live(conn, ~p"/endpoints")

      refute html =~ "Not mine"
    end

    test "creates a new endpoint", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/endpoints")

      view
      |> element(~s|a[href="#{~p"/endpoints/new"}"]|)
      |> render_click()

      assert_patch(view, ~p"/endpoints/new")

      view
      |> form("#endpoint-form", endpoint: %{name: "GitHub"})
      |> render_submit()

      assert_patch(view, ~p"/endpoints")
      assert render(view) =~ "GitHub"
    end

    test "rejects an endpoint with no name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/endpoints/new")

      html =
        view
        |> form("#endpoint-form", endpoint: %{name: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "redirects if the user is not logged in" do
      conn = Phoenix.ConnTest.build_conn()
      assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, ~p"/endpoints")
    end
  end
end
