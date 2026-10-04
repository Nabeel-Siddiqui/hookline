defmodule Hookline.Relay.Destination do
  @moduledoc """
  A real URL that an endpoint's events are forwarded to.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "destinations" do
    field :url, :string
    field :active, :boolean, default: true

    belongs_to :endpoint, Hookline.Relay.Endpoint
    has_many :delivery_attempts, Hookline.Relay.DeliveryAttempt

    timestamps(type: :utc_datetime)
  end

  @doc "Builds a changeset for a destination. The URL must be http or https."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(destination, attrs) do
    destination
    |> cast(attrs, [:url, :active])
    |> validate_required([:url])
    |> validate_change(:url, fn :url, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
          []

        _ ->
          [url: "must be an http or https URL"]
      end
    end)
  end
end
