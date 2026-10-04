defmodule Hookline.Relay.DeliveryAttempt do
  @moduledoc """
  One try at forwarding an event to a destination, and what happened.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:succeeded, :failed]

  @type t :: %__MODULE__{}

  schema "delivery_attempts" do
    field :attempt_number, :integer
    field :status, Ecto.Enum, values: @statuses
    field :response_code, :integer
    field :error, :string
    field :attempted_at, :utc_datetime_usec

    belongs_to :event, Hookline.Relay.Event
    belongs_to :destination, Hookline.Relay.Destination

    timestamps(type: :utc_datetime)
  end

  @doc "Builds a changeset recording one delivery attempt."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:attempt_number, :status, :response_code, :error, :attempted_at])
    |> validate_required([:attempt_number, :status, :attempted_at])
    |> validate_number(:attempt_number, greater_than: 0)
  end
end
