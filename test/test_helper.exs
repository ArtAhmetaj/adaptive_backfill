Mimic.copy(AdaptiveBackfill.Repo)

ExUnit.start()

AdaptiveBackfill.Repo.start_link([])

Ecto.Adapters.SQL.Sandbox.mode(AdaptiveBackfill.Repo, :manual)
