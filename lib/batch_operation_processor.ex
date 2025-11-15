defmodule BatchOperationProcessor do
  alias BatchOperationOptions
  alias MonitorResultEvaluator

  def process(%BatchOperationOptions{
        initial_state: initial_state,
        handle_batch: handle_batch,
        on_complete: on_complete,
        mode: mode,
        health_checkers: health_checkers
      }) do
    health_check_context = init_health_checks(mode, health_checkers)
    result = run_batch_cycle(initial_state, handle_batch, on_complete, mode, health_check_context)
    cleanup_health_checks(mode, health_check_context)
    result
  end

  def run_batch_cycle(state, handle_batch, on_complete, mode, health_check_context) do
    case handle_batch.(state) do
      :done ->
        if on_complete, do: on_complete.(:done)
        {:ok, :done}

      {:ok, next_state} ->
        monitor_results = run_health_checks(mode, health_check_context)

        if MonitorResultEvaluator.halt?(monitor_results) do
          if on_complete, do: on_complete.(next_state)
          {:halt, next_state}
        else
          run_batch_cycle(next_state, handle_batch, on_complete, mode, health_check_context)
        end

      {:error, _reason} = err ->
        err
    end
  end

  defp init_health_checks(:async, health_checkers) do
    {:ok, pid} = AsyncMonitor.start_link(health_checkers)
    pid
  end

  defp init_health_checks(:sync, health_checkers) do
    health_checkers
  end

  defp run_health_checks(:async, pid) do
    GenServer.call(pid, :get_state)
  end

  defp run_health_checks(:sync, health_checkers) do
    SyncMonitor.get_state(health_checkers)
  end

  defp cleanup_health_checks(:async, pid) do
    GenServer.stop(pid)
  end

  defp cleanup_health_checks(:sync, _health_checkers) do
    :ok
  end
end
