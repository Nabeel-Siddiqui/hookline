defmodule Hookline.Relay.HttpClient.ReqClient do
  @moduledoc "The real `HttpClient`, backed by Req."

  @behaviour Hookline.Relay.HttpClient

  @impl true
  def post(url, body, headers) do
    case Req.post(url, body: body, headers: headers, receive_timeout: 10_000, retry: false) do
      {:ok, %Req.Response{status: status}} -> {:ok, status}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end
end
