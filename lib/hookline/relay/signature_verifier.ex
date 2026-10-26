defmodule Hookline.Relay.SignatureVerifier do
  @moduledoc """
  Verifies an inbound webhook's HMAC-SHA256 signature against an
  endpoint's shared secret — the scheme GitHub, Shopify, and many other
  senders use: `sha256=<hex digest of the raw request body>`, keyed
  with a secret both sides hold. Stripe's own scheme folds a timestamp
  into the signed payload instead, and isn't implemented here — see
  the README's "what I'd do next".

  This module has no dependency on `Repo` or any other part of the
  app on purpose: it's a pure function of its three inputs, so it's
  tested directly rather than through a request.
  """

  @doc """
  `signature` is the raw header value, with or without a `sha256=`
  prefix — both GitHub's format (`sha256=<hex>`) and a bare hex digest
  are accepted. The comparison is constant-time, so a timing attack
  can't be used to guess the secret one byte at a time.
  """
  @spec verify?(String.t(), String.t(), binary()) :: boolean()
  def verify?(secret, signature, body)
      when is_binary(secret) and is_binary(signature) and is_binary(body) do
    expected =
      :hmac
      |> :crypto.mac(:sha256, secret, body)
      |> Base.encode16(case: :lower)

    Plug.Crypto.secure_compare(expected, strip_prefix(signature))
  end

  defp strip_prefix("sha256=" <> rest), do: rest
  defp strip_prefix(signature), do: signature
end
