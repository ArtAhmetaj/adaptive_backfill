defmodule AsyncMonitor do
  @moduledoc """
  Async monitor that does the healthcheck in the background and provides the state, nonblocking.
  """
  use GenServer

  alias Types
  alias Utils

  @timeout_in_ms 15_000
  @poll_time_in_ms 10_000

  @doc """
  Starts the GenServer.
  """
  def start_link(init_args) do
    GenServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  @doc """
  Gets the current state synchronously.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end



  @impl true
  def init(health_checkers) do

    start_polling()
    {:ok, zip_health_checks_with_state(health_checkers)}

  end

  @impl true
  def handle_call(:get_state, _from, state) do
    #TODO: health checkers should probably have an id.
    {:reply, state, state}
  end

  @impl true
  def handle_info(msg, state) do
   case msg do
     :poll ->
      new_state = poll_state(state)
      Process.send_after(self(), :poll, @poll_time_in_ms)
      {:no_reply, new_state}
   end
  end


  defp start_polling() do
    send(self(), :poll)
  end

  defp poll_state(state) do

    async_monitor_funcs = state
    |> Enum.map(fn {health_checker, _state} -> {health_checker, health_checker.()} end)
    |> Task.async()

    Task.await_many(async_monitor_funcs, @timeout_in_ms)
    |> case do
      {:error, reason} -> List.duplicate({:halt, reason}, length(state))
      awaited_responses -> awaited_responses

    end

  end


  defp zip_health_checks_with_state(health_checkers) do
  initial_ok_states = List.duplicate(:ok, length(health_checkers))
  Enum.zip(health_checkers, initial_ok_states)
end
end
