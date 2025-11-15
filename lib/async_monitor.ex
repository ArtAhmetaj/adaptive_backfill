defmodule AdaptiveBackfill.AsyncMonitor do
  @moduledoc """
  Async monitor that does the healthcheck in the background and provides the state, nonblocking.
  """
  use GenServer

  @timeout_in_ms 15_000
  @poll_time_in_ms 10_000

  @doc """
  Starts the GenServer.
  """
  def start_link(init_args) do
    GenServer.start_link(__MODULE__, init_args)
  end

  @doc """
  Gets the current state synchronously from a specific monitor PID.
  """
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @impl true
  def init(health_checkers) do
    start_polling()
    {:ok, zip_health_checks_with_state(health_checkers)}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    results = Enum.map(state, fn {_health_checker, result} -> result end)
    {:reply, results, state}
  end

  @impl true
  def handle_info(msg, state) do
    case msg do
      :poll ->
        new_state = poll_state(state)
        Process.send_after(self(), :poll, @poll_time_in_ms)
        {:noreply, new_state}
    end
  end

  defp start_polling() do
    send(self(), :poll)
  end

  defp poll_state(state) do
    tasks =
      state
      |> Enum.map(fn {health_checker, _state} -> Task.async(health_checker) end)

    results = Task.await_many(tasks, @timeout_in_ms)

    Enum.zip(state, results)
    |> Enum.map(fn {{health_checker, _old_result}, new_result} ->
      {health_checker, new_result}
    end)
  end

  defp zip_health_checks_with_state(health_checkers) do
    initial_ok_states = List.duplicate(:ok, length(health_checkers))
    Enum.zip(health_checkers, initial_ok_states)
  end
end
