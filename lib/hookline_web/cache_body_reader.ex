defmodule HooklineWeb.CacheBodyReader do
  @moduledoc """
  A `Plug.Parsers` `:body_reader` that stashes the raw request body in
  `conn.assigns[:raw_body]` before handing it to whichever parser (JSON,
  almost always, for a webhook sender) consumes it.

  Without this, `ReceiveController` would only ever see `conn.body_params`
  — Plug's re-decoded, re-encodable version of the body, not the exact
  bytes the sender transmitted. A captured-and-replayed webhook has to be
  byte-for-byte what was actually sent, not a reserialization of it.
  """

  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, Plug.Conn.assign(conn, :raw_body, body)}
      {:more, partial, conn} -> {:more, partial, conn}
      {:error, reason} -> {:error, reason}
    end
  end
end
