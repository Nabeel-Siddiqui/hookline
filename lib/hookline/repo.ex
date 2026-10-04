defmodule Hookline.Repo do
  use Ecto.Repo,
    otp_app: :hookline,
    adapter: Ecto.Adapters.Postgres
end
