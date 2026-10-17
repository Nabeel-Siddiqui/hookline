defmodule Hookline.Relay.DeliveryWorkerTest do
  use Hookline.DataCase, async: true
  use Oban.Testing, repo: Hookline.Repo

  import Hookline.AccountsFixtures
  import Hookline.RelayFixtures
  import Mox

  alias Hookline.Relay
  alias Hookline.Relay.DeliveryWorker

  setup :verify_on_exit!

  describe "perform/1" do
    test "a 2xx response is recorded as succeeded and the job succeeds" do
      user = user_fixture()
      endpoint = endpoint_fixture(user)
      destination = destination_fixture(user, endpoint)
      event = event_fixture(endpoint)

      expect(Hookline.Relay.HttpClientMock, :post, fn url, body, _headers ->
        assert url == destination.url
        assert body == event.body
        {:ok, 200}
      end)

      assert :ok =
               perform_job(DeliveryWorker, %{event_id: event.id, destination_id: destination.id})

      assert [attempt] = Relay.list_attempts(event)
      assert attempt.status == :succeeded
      assert attempt.response_code == 200
      assert attempt.attempt_number == 1
    end

    test "a non-2xx response is recorded as failed and the job errors, for Oban to retry" do
      user = user_fixture()
      endpoint = endpoint_fixture(user)
      destination = destination_fixture(user, endpoint)
      event = event_fixture(endpoint)

      expect(Hookline.Relay.HttpClientMock, :post, fn _url, _body, _headers -> {:ok, 503} end)

      assert {:error, _reason} =
               perform_job(DeliveryWorker, %{event_id: event.id, destination_id: destination.id})

      assert [attempt] = Relay.list_attempts(event)
      assert attempt.status == :failed
      assert attempt.response_code == 503
    end

    test "a connection error is recorded as failed and the job errors" do
      user = user_fixture()
      endpoint = endpoint_fixture(user)
      destination = destination_fixture(user, endpoint)
      event = event_fixture(endpoint)

      expect(Hookline.Relay.HttpClientMock, :post, fn _url, _body, _headers ->
        {:error, :econnrefused}
      end)

      assert {:error, :econnrefused} =
               perform_job(DeliveryWorker, %{event_id: event.id, destination_id: destination.id})

      assert [attempt] = Relay.list_attempts(event)
      assert attempt.status == :failed
      assert attempt.error =~ "econnrefused"
    end

    test "forwards the event's own headers, except the hop-by-hop ones" do
      user = user_fixture()
      endpoint = endpoint_fixture(user)
      destination = destination_fixture(user, endpoint)

      event =
        event_fixture(endpoint, %{
          headers: %{
            "content-type" => "application/json",
            "x-signature" => "sig123",
            "host" => "hookline.example.com",
            "content-length" => "42"
          }
        })

      expect(Hookline.Relay.HttpClientMock, :post, fn _url, _body, headers ->
        header_keys = Enum.map(headers, &elem(&1, 0))
        assert "content-type" in header_keys
        assert "x-signature" in header_keys
        refute "host" in header_keys
        refute "content-length" in header_keys
        {:ok, 200}
      end)

      assert :ok =
               perform_job(DeliveryWorker, %{event_id: event.id, destination_id: destination.id})
    end

    test "uses the current attempt number, not always 1, on a retried job" do
      user = user_fixture()
      endpoint = endpoint_fixture(user)
      destination = destination_fixture(user, endpoint)
      event = event_fixture(endpoint)

      expect(Hookline.Relay.HttpClientMock, :post, fn _url, _body, _headers -> {:ok, 200} end)

      assert :ok =
               perform_job(
                 DeliveryWorker,
                 %{event_id: event.id, destination_id: destination.id},
                 attempt: 3
               )

      assert [attempt] = Relay.list_attempts(event)
      assert attempt.attempt_number == 3
    end
  end

  describe "backoff/1" do
    test "doubles each attempt: 1s, 2s, 4s, 8s, 16s" do
      assert DeliveryWorker.backoff(%Oban.Job{attempt: 1}) == 1
      assert DeliveryWorker.backoff(%Oban.Job{attempt: 2}) == 2
      assert DeliveryWorker.backoff(%Oban.Job{attempt: 3}) == 4
      assert DeliveryWorker.backoff(%Oban.Job{attempt: 4}) == 8
      assert DeliveryWorker.backoff(%Oban.Job{attempt: 5}) == 16
    end
  end
end
