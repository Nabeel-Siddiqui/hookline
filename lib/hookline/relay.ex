defmodule Hookline.Relay do
  @moduledoc """
  Endpoints, their destinations, the events captured on them, and the
  delivery attempts made for each event.

  Every function that reads or writes an endpoint takes the owning user
  and returns `{:error, :not_found}` for someone else's endpoint, so a
  guessed id reveals nothing.
  """

  import Ecto.Query, warn: false

  alias Hookline.Accounts.User

  alias Hookline.Relay.{
    DeliveryAttempt,
    DeliveryWorker,
    Destination,
    Endpoint,
    Event,
    SignatureVerifier
  }

  alias Hookline.Repo

  @doc "Returns a changeset for tracking a new endpoint's form changes, without persisting anything."
  @spec create_endpoint_changeset(map()) :: Ecto.Changeset.t()
  def create_endpoint_changeset(attrs \\ %{}) do
    Endpoint.create_changeset(%Endpoint{}, attrs)
  end

  @doc "Creates an endpoint owned by `user`. The public token is generated here."
  @spec create_endpoint(User.t(), map()) :: {:ok, Endpoint.t()} | {:error, Ecto.Changeset.t()}
  def create_endpoint(%User{} = user, attrs) do
    %Endpoint{user_id: user.id}
    |> Endpoint.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Fetches an endpoint by id, scoped to `user`."
  @spec get_endpoint(User.t(), term()) :: {:ok, Endpoint.t()} | {:error, :not_found}
  def get_endpoint(%User{} = user, id) do
    with {:ok, int_id} <- cast_id(id),
         %Endpoint{} = endpoint <- Repo.get_by(Endpoint, id: int_id, user_id: user.id) do
      {:ok, endpoint}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Looks up an endpoint by its public token. Used by the receiving URL,
  where the sender is not logged in, so there is no user to scope by.
  """
  @spec get_endpoint_by_token(String.t()) :: {:ok, Endpoint.t()} | {:error, :not_found}
  def get_endpoint_by_token(token) when is_binary(token) do
    case Repo.get_by(Endpoint, token: token) do
      %Endpoint{} = endpoint -> {:ok, endpoint}
      nil -> {:error, :not_found}
    end
  end

  @doc "Lists `user`'s endpoints, newest first."
  @spec list_endpoints(User.t()) :: [Endpoint.t()]
  def list_endpoints(%User{} = user) do
    Endpoint
    |> where([e], e.user_id == ^user.id)
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> Repo.all()
  end

  @doc "Returns a changeset for editing `endpoint`'s signature header, without persisting anything."
  @spec change_endpoint_signature(Endpoint.t(), map()) :: Ecto.Changeset.t()
  def change_endpoint_signature(%Endpoint{} = endpoint, attrs \\ %{}) do
    Endpoint.signature_changeset(endpoint, attrs)
  end

  @doc """
  Updates which header `endpoint` expects a sender's signature in,
  scoped to `user`. Setting it to a blank value turns verification
  back off for this endpoint.
  """
  @spec update_endpoint_signature(User.t(), Endpoint.t(), map()) ::
          {:ok, Endpoint.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def update_endpoint_signature(%User{} = user, %Endpoint{} = endpoint, attrs) do
    with {:ok, endpoint} <- get_endpoint(user, endpoint.id) do
      endpoint
      |> Endpoint.signature_changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Regenerates `endpoint`'s signing secret, scoped to `user`. The old
  secret stops verifying anything immediately — any sender still using
  it starts failing verification until it's given the new one.
  """
  @spec regenerate_endpoint_signing_secret(User.t(), Endpoint.t()) ::
          {:ok, Endpoint.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def regenerate_endpoint_signing_secret(%User{} = user, %Endpoint{} = endpoint) do
    with {:ok, endpoint} <- get_endpoint(user, endpoint.id) do
      endpoint
      |> Endpoint.regenerate_signing_secret_changeset()
      |> Repo.update()
    end
  end

  @doc """
  Whether `raw_body` carries a valid signature for `endpoint`, given
  the request's `headers` (a map, the same shape `record_event/2`
  stores). An endpoint with no `signature_header` configured has
  verification turned off entirely, so this always returns `true` —
  the same "nothing configured, let it through" behavior every
  endpoint had before this feature existed.
  """
  @spec valid_signature?(Endpoint.t(), map(), binary()) :: boolean()
  def valid_signature?(%Endpoint{signature_header: header}, _headers, _body)
      when header in [nil, ""],
      do: true

  def valid_signature?(%Endpoint{signing_secret: nil}, _headers, _body), do: false

  def valid_signature?(%Endpoint{} = endpoint, headers, body) when is_map(headers) do
    header_name = String.downcase(endpoint.signature_header)

    case Map.fetch(headers, header_name) do
      {:ok, signature} -> SignatureVerifier.verify?(endpoint.signing_secret, signature, body)
      :error -> false
    end
  end

  @doc "Returns a changeset for tracking a new destination's form changes, without persisting anything."
  @spec create_destination_changeset(map()) :: Ecto.Changeset.t()
  def create_destination_changeset(attrs \\ %{}) do
    Destination.changeset(%Destination{}, attrs)
  end

  @doc "Adds a destination to `endpoint`, scoped to `user`."
  @spec create_destination(User.t(), Endpoint.t(), map()) ::
          {:ok, Destination.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def create_destination(%User{} = user, %Endpoint{} = endpoint, attrs) do
    with {:ok, endpoint} <- get_endpoint(user, endpoint.id) do
      %Destination{endpoint_id: endpoint.id}
      |> Destination.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc "Lists `endpoint`'s destinations. The endpoint's ownership is checked once, where it was loaded."
  @spec list_destinations(Endpoint.t()) :: [Destination.t()]
  def list_destinations(%Endpoint{} = endpoint) do
    Destination
    |> where([d], d.endpoint_id == ^endpoint.id)
    |> order_by([d], asc: d.id)
    |> Repo.all()
  end

  @doc """
  Stores a captured request on `endpoint`. Returns a changeset error if
  the body is over the size limit, and the event is not stored.
  """
  @spec record_event(Endpoint.t(), map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def record_event(%Endpoint{} = endpoint, attrs) do
    with {:ok, event} <-
           %Event{endpoint_id: endpoint.id} |> Event.changeset(attrs) |> Repo.insert() do
      broadcast(endpoint.id, {:event_captured, event})
      {:ok, event}
    end
  end

  @doc "Lists `endpoint`'s events, newest first."
  @spec list_events(Endpoint.t()) :: [Event.t()]
  def list_events(%Endpoint{} = endpoint) do
    Event
    |> where([e], e.endpoint_id == ^endpoint.id)
    |> order_by([e], desc: e.received_at, desc: e.id)
    |> Repo.all()
  end

  @doc "Fetches an event by id, scoped to `endpoint`."
  @spec get_event(Endpoint.t(), term()) :: {:ok, Event.t()} | {:error, :not_found}
  def get_event(%Endpoint{} = endpoint, id) do
    with {:ok, int_id} <- cast_id(id),
         %Event{} = event <- Repo.get_by(Event, id: int_id, endpoint_id: endpoint.id) do
      {:ok, event}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Subscribes the caller to `endpoint`'s events: `{:event_captured, event}`
  as each one is captured, and `{:attempt_recorded, attempt}` as each
  delivery attempt for any of its events happens.
  """
  @spec subscribe_to_endpoint(Endpoint.t()) :: :ok | {:error, term()}
  def subscribe_to_endpoint(%Endpoint{} = endpoint) do
    Phoenix.PubSub.subscribe(Hookline.PubSub, endpoint_topic(endpoint.id))
  end

  @doc """
  Fetches an event by id, with no user scoping. Used by `DeliveryWorker`,
  which runs as a background job with no user in the picture — only the
  id Oban was given when the job was enqueued.
  """
  @spec get_event_for_delivery(term()) :: {:ok, Event.t()} | {:error, :not_found}
  def get_event_for_delivery(id) do
    with {:ok, int_id} <- cast_id(id),
         %Event{} = event <- Repo.get(Event, int_id) do
      {:ok, event}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Fetches a destination by id, with no user scoping. Same reasoning as `get_event_for_delivery/1`."
  @spec get_destination_for_delivery(term()) :: {:ok, Destination.t()} | {:error, :not_found}
  def get_destination_for_delivery(id) do
    with {:ok, int_id} <- cast_id(id),
         %Destination{} = destination <- Repo.get(Destination, int_id) do
      {:ok, destination}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Enqueues a delivery job for `event` against every active destination
  on its endpoint. Used both right after an event is captured, and to
  replay a past event on demand — the same fan-out either way.
  """
  @spec enqueue_deliveries(Event.t()) :: :ok
  def enqueue_deliveries(%Event{} = event) do
    event = Repo.preload(event, endpoint: :destinations)

    jobs =
      for destination <- event.endpoint.destinations, destination.active do
        DeliveryWorker.new(%{event_id: event.id, destination_id: destination.id})
      end

    # insert_all/1 is one bulk insert, not N individual ones each with
    # its own result to check — there's no per-row changeset validation
    # to fail here (the args are always valid, already-persisted ids),
    # only a genuine infrastructure failure, which should raise rather
    # than be swallowed by checking a result that's never meaningfully
    # an {:error, _}.
    Oban.insert_all(jobs)
    :ok
  end

  @doc "Records one delivery attempt of `event` to `destination`."
  @spec record_attempt(Event.t(), Destination.t(), map()) ::
          {:ok, DeliveryAttempt.t()} | {:error, Ecto.Changeset.t()}
  def record_attempt(%Event{} = event, %Destination{} = destination, attrs) do
    with {:ok, attempt} <-
           %DeliveryAttempt{event_id: event.id, destination_id: destination.id}
           |> DeliveryAttempt.changeset(attrs)
           |> Repo.insert() do
      broadcast(event.endpoint_id, {:attempt_recorded, attempt})
      {:ok, attempt}
    end
  end

  @doc "Lists the delivery attempts made for `event`, in the order they happened."
  @spec list_attempts(Event.t()) :: [DeliveryAttempt.t()]
  def list_attempts(%Event{} = event) do
    DeliveryAttempt
    |> where([a], a.event_id == ^event.id)
    |> order_by([a], asc: a.attempted_at, asc: a.id)
    |> Repo.all()
  end

  defp cast_id(id) do
    case Integer.parse(to_string(id)) do
      {int_id, ""} -> {:ok, int_id}
      _ -> :error
    end
  end

  defp broadcast(endpoint_id, message) do
    Phoenix.PubSub.broadcast(Hookline.PubSub, endpoint_topic(endpoint_id), message)
  end

  defp endpoint_topic(endpoint_id), do: "endpoint:#{endpoint_id}"
end
