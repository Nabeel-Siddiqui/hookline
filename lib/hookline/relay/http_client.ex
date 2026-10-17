defmodule Hookline.Relay.HttpClient do
  @moduledoc """
  What `DeliveryWorker` needs from an HTTP client to forward a captured
  event to its destination. Nothing in `lib/` calls `Req` (or anything
  else) directly — the real implementation and the Mox test double both
  implement this.
  """

  @doc "POSTs `body` to `url` with `headers`, returning the response status or an error."
  @callback post(url :: String.t(), body :: String.t(), headers :: [{String.t(), String.t()}]) ::
              {:ok, status :: non_neg_integer()} | {:error, term()}
end
