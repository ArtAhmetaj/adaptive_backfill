defmodule AdaptiveBackfill.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AdaptiveBackfill.Repo
    ]

    opts = [strategy: :one_for_one, name: AdaptiveBackfill.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
