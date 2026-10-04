defmodule Hookline.Relay.Endpoint do
  @moduledoc """
  A receiving URL owned by a user. Anything POSTed to `/in/:token` is
  captured as an event on this endpoint.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "endpoints" do
    field :token, :string
    field :name, :string

    belongs_to :user, Hookline.Accounts.User
    has_many :destinations, Hookline.Relay.Destination
    has_many :events, Hookline.Relay.Event

    timestamps(type: :utc_datetime)
  end

  @doc "Builds a changeset for a new endpoint, generating its public token."
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> put_token()
    |> unique_constraint(:token)
  end

  defp put_token(changeset) do
    token = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    put_change(changeset, :token, token)
  end
end
