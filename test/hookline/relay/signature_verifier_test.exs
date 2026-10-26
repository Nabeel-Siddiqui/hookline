defmodule Hookline.Relay.SignatureVerifierTest do
  use ExUnit.Case, async: true

  alias Hookline.Relay.SignatureVerifier

  @secret "shared-secret"
  @body ~s({"id":"evt_1"})

  defp hex_hmac(secret, body) do
    :hmac
    |> :crypto.mac(:sha256, secret, body)
    |> Base.encode16(case: :lower)
  end

  describe "verify?/3" do
    test "accepts a bare hex digest" do
      signature = hex_hmac(@secret, @body)

      assert SignatureVerifier.verify?(@secret, signature, @body)
    end

    test "accepts GitHub's sha256= prefixed form" do
      signature = "sha256=" <> hex_hmac(@secret, @body)

      assert SignatureVerifier.verify?(@secret, signature, @body)
    end

    test "rejects a signature computed with the wrong secret" do
      signature = hex_hmac("some-other-secret", @body)

      refute SignatureVerifier.verify?(@secret, signature, @body)
    end

    test "rejects a signature computed over a different body" do
      signature = hex_hmac(@secret, @body)

      refute SignatureVerifier.verify?(@secret, signature, "tampered body")
    end

    test "rejects garbage" do
      refute SignatureVerifier.verify?(@secret, "not-a-real-signature", @body)
    end

    test "rejects an empty signature" do
      refute SignatureVerifier.verify?(@secret, "", @body)
    end
  end
end
