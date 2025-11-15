Mimic.copy(AdaptiveBackfill.Repo)

ExUnit.start()

{:ok, _} = Application.ensure_all_started(:adaptive_backfill)

Ecto.Adapters.SQL.Sandbox.mode(AdaptiveBackfill.Repo, :manual)
