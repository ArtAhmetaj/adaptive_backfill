import Config

config :adaptive_backfill, AdaptiveBackfill.Repo,
  database: "adaptive_backfill_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox
