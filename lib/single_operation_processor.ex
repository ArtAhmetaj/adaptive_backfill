defmodule SingleOperationProcessor do

  alias SingleOperationOptions


  def process(%SingleOperationOptions{handle: handle, on_complete: on_complete, mode: mode, health_checkers: health_checkers}) do
    #we need to provide

    health_cb = build_health_check_callback(mode, health_checkers)

    case handle.(health_cb) do
      {:ok, _returned_state} -> handle.(health_cb)
      {:halt, returned_state} ->
        if !is_nil(on_complete) do
          on_complete.(returned_state)
          returned_state
        else
          returned_state
        end
    end


  end


  defp build_health_check_callback(:async, health_checkers) do
    {:ok, pid} = AsyncMonitor.start_link(health_checkers)
    #TODO: have genserver be killed by new_state and halt to handle lifecycle of process
  fn _ ->
    GenServer.call(pid, :get_state)
  end
  end

  defp build_health_check_callback(:sync, health_checkers) do

    fn _ ->
      SyncMonitor.get_state(health_checkers)
    end
  end


end
