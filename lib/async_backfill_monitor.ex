defmodule AdaptiveBackfill.AsyncBackfillMonitor do
  @moduledoc """
  Monitors async backfill operations. Provides state of provided health checks, to see if system is still valid.
  """
  use GenServer

  def start_link(init_state) do
    GenServer.start_link(__MODULE__, %{state: init_state}, name: __MODULE__)
  end

  def get_monitored_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @impl true
  def init(initial_state) do
    {:ok, initial_state}
  end

  # Handle synchronous calls
  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_operation}, state}
  end
end
