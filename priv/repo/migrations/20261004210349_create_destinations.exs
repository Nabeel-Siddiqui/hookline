defmodule Hookline.Repo.Migrations.CreateDestinations do
  use Ecto.Migration

  def change do
    create table(:destinations) do
      add :url, :string, null: false
      add :active, :boolean, null: false, default: true
      add :endpoint_id, references(:endpoints, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:destinations, [:endpoint_id])
  end
end
