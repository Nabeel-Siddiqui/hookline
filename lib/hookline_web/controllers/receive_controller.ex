defmodule HooklineWeb.ReceiveController do
  @moduledoc """
  The public receiving URL: `POST /in/:token`. Captures the request
  exactly as sent and stores it as an event. No authentication — the
  token in the URL is the only credential a sender has, the same as any
  webhook receiving URL (Stripe's, GitHub's, ...).
  """

  use HooklineWeb, :controller

  alias Hookline.Relay
  alias Hookline.Relay.Event

  def create(conn, %{"token" => token}) do
    with {:ok, endpoint} <- Relay.get_endpoint_by_token(token),
         {:ok, body, conn} <- raw_body(conn) do
      attrs = %{
        method: conn.method,
        headers: Map.new(conn.req_headers),
        body: body,
        received_at: DateTime.utc_now()
      }

      case Relay.record_event(endpoint, attrs) do
        {:ok, _event} -> send_resp(conn, 200, "")
        {:error, _changeset} -> send_resp(conn, 413, "payload too large")
      end
    else
      {:error, :not_found} -> send_resp(conn, 404, "")
      {:error, :too_large, conn} -> send_resp(conn, 413, "payload too large")
    end
  end

  # HooklineWeb.CacheBodyReader already stashed the body when Plug.Parsers
  # matched this request's content type (the common case — a webhook
  # sender almost always sends JSON). For a content type no configured
  # parser claims, Plug.Parsers leaves the body unread entirely, so it's
  # read here instead, with the same size cap.
  defp raw_body(%{assigns: %{raw_body: body}} = conn), do: {:ok, body, conn}

  defp raw_body(conn) do
    case Plug.Conn.read_body(conn, length: Event.max_body_bytes()) do
      {:ok, body, conn} -> {:ok, body, conn}
      {:more, _partial, conn} -> {:error, :too_large, conn}
    end
  end
end
