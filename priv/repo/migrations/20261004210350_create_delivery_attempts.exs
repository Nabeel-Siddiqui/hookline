defmodule Hookline.Repo.Migrations.CreateDeliveryAttempts do
  use Ecto.Migration

  def change do
    create table(:delivery_attempts) do
      add :attempt_number, :integer, null: false
      add :status, :string, null: false
      add :response_code, :integer
      add :error, :text
      add :attempted_at, :utc_datetime_usec, null: false
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :destination_id, references(:destinations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:delivery_attempts, [:event_id])
    create index(:delivery_attempts, [:destination_id])
  end
end
