defmodule BatchOperationProcessor do
  alias BatchOperationOptions

  def process(%BatchOperationOptions{
        initial_state: initial_state,
        handle_batch: handle_batch,
        on_complete: on_complete,
        mode: mode,
        health_checkers: health_checkers
      }) do

    health_checker = build_health_check_callback(mode, health_checkers)

    with {:ok, state_after_batch} <- handle_batch.(initial_state),
         :ok <- health_checker.(),
         {:ok, final_state} <- handle_batch.(state_after_batch) do
      final_state
    else
      {:halt, reason} = halt ->
        on_complete.(reason)
        halt

      other ->
        other
    end
  end


  defp build_health_check_callback(:async, health_checkers) do
    {:ok, pid} = AsyncMonitor.start_link(health_checkers)

    fn ->
      GenServer.call(pid, :get_state)
    end
  end

  defp build_health_check_callback(:sync, health_checkers) do
    fn ->
      SyncMonitor.get_state(health_checkers)
    end
  end
end
