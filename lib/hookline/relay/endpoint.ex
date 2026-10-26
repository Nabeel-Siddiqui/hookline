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
    field :signing_secret, :string
    field :signature_header, :string

    belongs_to :user, Hookline.Accounts.User
    has_many :destinations, Hookline.Relay.Destination
    has_many :events, Hookline.Relay.Event

    timestamps(type: :utc_datetime)
  end

  @doc "Builds a changeset for a new endpoint, generating its public token and signing secret."
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> put_token()
    |> put_signing_secret()
    |> unique_constraint(:token)
  end

  @doc """
  Builds a changeset for editing which header a sender's signature
  arrives in. The secret itself is never editable here — generating a
  new one goes through `regenerate_signing_secret_changeset/1` instead,
  since the two are different operations (one's a form field, the
  other invalidates whatever the sender currently has configured).
  """
  @spec signature_changeset(t(), map()) :: Ecto.Changeset.t()
  def signature_changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [:signature_header])
    |> validate_length(:signature_header, max: 100)
  end

  @doc "Builds a changeset that regenerates just the signing secret, leaving every other field untouched."
  @spec regenerate_signing_secret_changeset(t()) :: Ecto.Changeset.t()
  def regenerate_signing_secret_changeset(endpoint) do
    endpoint
    |> change()
    |> put_signing_secret()
  end

  defp put_token(changeset) do
    token = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    put_change(changeset, :token, token)
  end

  defp put_signing_secret(changeset) do
    secret = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    put_change(changeset, :signing_secret, secret)
  end
end
