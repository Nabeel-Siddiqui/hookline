defmodule Hookline.Repo.Migrations.AddSignatureVerificationToEndpoints do
  use Ecto.Migration

  # Both columns are nullable: an endpoint with no signature_header has
  # verification turned off entirely (the behavior every endpoint had
  # before this feature existed), and every endpoint created from here
  # on gets a signing_secret generated for it automatically — see
  # Endpoint.create_changeset/2. There's no backfill for endpoints that
  # already existed before this migration; the dashboard's "Regenerate"
  # button covers that case lazily, since this is dev/demo data, not a
  # production dataset with real senders depending on an existing secret.
  def change do
    alter table(:endpoints) do
      add :signing_secret, :string
      add :signature_header, :string
    end
  end
end
