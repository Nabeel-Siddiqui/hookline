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
  alias Hookline.Relay.{DeliveryAttempt, Destination, Endpoint, Event}
  alias Hookline.Repo

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
    %Event{endpoint_id: endpoint.id}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Lists `endpoint`'s events, newest first."
  @spec list_events(Endpoint.t()) :: [Event.t()]
  def list_events(%Endpoint{} = endpoint) do
    Event
    |> where([e], e.endpoint_id == ^endpoint.id)
    |> order_by([e], desc: e.received_at, desc: e.id)
    |> Repo.all()
  end

  @doc "Records one delivery attempt of `event` to `destination`."
  @spec record_attempt(Event.t(), Destination.t(), map()) ::
          {:ok, DeliveryAttempt.t()} | {:error, Ecto.Changeset.t()}
  def record_attempt(%Event{} = event, %Destination{} = destination, attrs) do
    %DeliveryAttempt{event_id: event.id, destination_id: destination.id}
    |> DeliveryAttempt.changeset(attrs)
    |> Repo.insert()
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
end
