defmodule Coinflips.Repo do
  use Ecto.Repo,
    otp_app: :coinflips,
    adapter: Ecto.Adapters.Postgres
end
