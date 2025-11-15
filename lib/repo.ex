defmodule AdaptiveBackfill.Repo do
  use Ecto.Repo,
    otp_app: :adaptive_backfill,
    adapter: Ecto.Adapters.Postgres
end
