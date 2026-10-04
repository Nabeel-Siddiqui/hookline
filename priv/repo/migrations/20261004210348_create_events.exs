defmodule Hookline.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :method, :string, null: false
      add :headers, :map, null: false, default: %{}
      add :body, :text, null: false, default: ""
      add :received_at, :utc_datetime_usec, null: false
      add :endpoint_id, references(:endpoints, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:endpoint_id, :received_at])
  end
end
