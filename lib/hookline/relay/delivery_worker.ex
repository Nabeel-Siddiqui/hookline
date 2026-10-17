defmodule Hookline.Relay.DeliveryWorker do
  @moduledoc """
  Forwards one event to one destination, and records what happened.
  Up to 5 attempts, with exponential backoff (1s, 2s, 4s, 8s, 16s)
  between them — Oban's own retry/backoff mechanism is the retry
  policy, not a hand-rolled loop. After the 5th failed attempt, Oban
  discards the job; the DeliveryAttempt rows already give full history,
  so there's nothing more for this worker to do at that point.

  A 2xx response is the only outcome that counts as success. Anything
  else — a non-2xx status, a timeout, a connection refusal — is
  recorded as a failed attempt and returned as `{:error, _}`, which is
  what tells Oban to schedule a retry.
  """

  use Oban.Worker, queue: :deliveries, max_attempts: 5

  alias Hookline.Relay

  # Headers that describe *this* request (its length, which connection
  # it arrived on) rather than the payload itself — forwarding them
  # verbatim would describe the wrong request to the destination.
  # Everything else, including a sender's own signature header, is
  # forwarded as-is: the destination's own signature verification
  # depends on seeing exactly what the original sender sent.
  @excluded_headers ~w(host content-length connection)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    round(:math.pow(2, attempt - 1))
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"event_id" => event_id, "destination_id" => destination_id},
        attempt: attempt
      }) do
    with {:ok, event} <- Relay.get_event_for_delivery(event_id),
         {:ok, destination} <- Relay.get_destination_for_delivery(destination_id) do
      deliver(event, destination, attempt)
    end
  end

  defp deliver(event, destination, attempt) do
    headers = forwardable_headers(event.headers)

    case http_client().post(destination.url, event.body, headers) do
      {:ok, status} when status in 200..299 ->
        record(event, destination, attempt, :succeeded, status, nil)
        :ok

      {:ok, status} ->
        record(event, destination, attempt, :failed, status, nil)
        {:error, "destination responded #{status}"}

      {:error, reason} ->
        record(event, destination, attempt, :failed, nil, inspect(reason))
        {:error, reason}
    end
  end

  defp record(event, destination, attempt, status, response_code, error) do
    Relay.record_attempt(event, destination, %{
      attempt_number: attempt,
      status: status,
      response_code: response_code,
      error: error,
      attempted_at: DateTime.utc_now()
    })
  end

  defp forwardable_headers(headers) do
    Enum.reject(headers, fn {key, _value} -> String.downcase(key) in @excluded_headers end)
  end

  defp http_client,
    do: Application.get_env(:hookline, :http_client, Hookline.Relay.HttpClient.ReqClient)
end
