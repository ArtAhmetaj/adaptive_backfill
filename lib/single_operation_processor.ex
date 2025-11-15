defmodule SingleOperationProcessor do
  alias SingleOperationOptions
  alias MonitorResultEvaluator

  def process(%SingleOperationOptions{
        handle: handle,
        on_complete: on_complete,
        mode: mode,
        health_checkers: health_checkers
      }) do
    health_cb = build_health_check_callback(mode, health_checkers)

    result = handle.(health_cb)

    case result do
      :done ->
        if on_complete, do: on_complete.(:done)
        {:ok, :done}

      {:ok, state} ->
        if on_complete, do: on_complete.(state)
        {:ok, state}

      {:halt, state} ->
        if on_complete, do: on_complete.(state)
        {:halt, state}

      {:error, _reason} = err ->
        err
    end
  end

  defp build_health_check_callback(:async, health_checkers) do
    {:ok, pid} = AsyncMonitor.start_link(health_checkers)

    fn ->
      monitor_results = GenServer.call(pid, :get_state)

      if MonitorResultEvaluator.halt?(monitor_results) do
        {:halt, monitor_results}
      else
        :ok
      end
    end
  end

  defp build_health_check_callback(:sync, health_checkers) do
    fn ->
      monitor_results = SyncMonitor.get_state(health_checkers)

      if MonitorResultEvaluator.halt?(monitor_results) do
        {:halt, monitor_results}
      else
        :ok
      end
    end
  end
end
