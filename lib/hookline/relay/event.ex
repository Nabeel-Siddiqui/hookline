defmodule Hookline.Relay.Event do
  @moduledoc """
  One captured inbound request: the method, headers, and body exactly as
  the sender posted them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  # 256 KB. Measured in bytes, not characters, because that's what a
  # sender actually transmits and what Postgres stores.
  @max_body_bytes 256 * 1024

  @type t :: %__MODULE__{}

  schema "events" do
    field :method, :string
    field :headers, :map, default: %{}
    field :body, :string, default: ""
    field :received_at, :utc_datetime_usec

    belongs_to :endpoint, Hookline.Relay.Endpoint
    has_many :delivery_attempts, Hookline.Relay.DeliveryAttempt

    timestamps(type: :utc_datetime)
  end

  @doc "The largest body an event will accept, in bytes."
  def max_body_bytes, do: @max_body_bytes

  @doc "Builds a changeset for a captured request. Rejects bodies over the limit."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:method, :headers, :body, :received_at])
    |> validate_required([:method, :received_at])
    |> validate_body_size()
  end

  defp validate_body_size(changeset) do
    validate_change(changeset, :body, fn :body, body ->
      if byte_size(body) > @max_body_bytes do
        [body: "must be at most #{@max_body_bytes} bytes"]
      else
        []
      end
    end)
  end
end
