defmodule SyncMonitor do

  @base_timeout_in_ms 15_000

  def get_state(health_checkers) do

    health_checkers |>
    Enum.map(fn func -> Task.async(func.()) end)
    |>
    Task.await_many(15_000)
    |>
    case do
      {:error, reason} -> List.duplicate({:halt, reason}, length(health_checkers))
      awaited_response -> awaited_response
    end
  end
end
