defmodule AdaptiveBackfill.Checkpoint do
  @moduledoc """
  Checkpoint configuration for backfill operations.

  Allows saving and restoring state so backfills can resume from where they stopped.
  """

  @type t :: %__MODULE__{
          adapter: module(),
          name: String.t() | atom()
        }

  defstruct [:adapter, :name]

  @doc """
  Creates a new checkpoint configuration.
  """
  def new(adapter, name) do
    %__MODULE__{adapter: adapter, name: name}
  end

  @doc """
  Saves state using the checkpoint configuration.
  """
  def save(%__MODULE__{adapter: adapter, name: name}, state) do
    adapter.save(name, state)
  end

  def save(nil, _state), do: :ok

  @doc """
  Loads state using the checkpoint configuration.
  """
  def load(%__MODULE__{adapter: adapter, name: name}) do
    adapter.load(name)
  end

  def load(nil), do: {:error, :not_found}

  @doc """
  Deletes a checkpoint using the configuration.
  """
  def delete(%__MODULE__{adapter: adapter, name: name}) do
    adapter.delete(name)
  end

  def delete(nil), do: :ok

  @type checkpoint_name :: String.t() | atom()
  @type state :: any()
  @type error :: any()

  @doc """
  Callback for checkpoint adapters to save state.
  """
  @callback save(checkpoint_name(), state()) :: :ok | {:error, error()}

  @doc """
  Callback for checkpoint adapters to load state.
  """
  @callback load(checkpoint_name()) :: {:ok, state()} | {:error, error()}

  @doc """
  Callback for checkpoint adapters to delete state.
  """
  @callback delete(checkpoint_name()) :: :ok | {:error, error()}

  defmodule Memory do
    @moduledoc """
    In-memory checkpoint adapter for testing.
    """
    @behaviour AdaptiveBackfill.Checkpoint
    use Agent

    def start_link(_opts \\ []) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    @impl true
    def save(name, state) do
      ensure_started()
      Agent.update(__MODULE__, &Map.put(&1, to_string(name), state))
      :ok
    end

    @impl true
    def load(name) do
      ensure_started()

      case Agent.get(__MODULE__, &Map.get(&1, to_string(name))) do
        nil -> {:error, :not_found}
        state -> {:ok, state}
      end
    end

    @impl true
    def delete(name) do
      ensure_started()
      Agent.update(__MODULE__, &Map.delete(&1, to_string(name)))
      :ok
    end

    def clear do
      ensure_started()
      Agent.update(__MODULE__, fn _ -> %{} end)
    end

    defp ensure_started do
      case Process.whereis(__MODULE__) do
        nil -> start_link()
        _pid -> :ok
      end
    end
  end

  defmodule ETS do
    @moduledoc """
    ETS-based checkpoint adapter.
    """
    @behaviour AdaptiveBackfill.Checkpoint
    @table_name :adaptive_backfill_checkpoints

    def start_link(_opts \\ []) do
      case :ets.whereis(@table_name) do
        :undefined ->
          :ets.new(@table_name, [:named_table, :public, :set])
          {:ok, self()}

        _ref ->
          {:ok, self()}
      end
    end

    @impl true
    def save(name, state) do
      ensure_started()
      :ets.insert(@table_name, {to_string(name), state})
      :ok
    end

    @impl true
    def load(name) do
      ensure_started()

      case :ets.lookup(@table_name, to_string(name)) do
        [{_, state}] -> {:ok, state}
        [] -> {:error, :not_found}
      end
    end

    @impl true
    def delete(name) do
      ensure_started()
      :ets.delete(@table_name, to_string(name))
      :ok
    end

    def clear do
      ensure_started()
      :ets.delete_all_objects(@table_name)
    end

    defp ensure_started do
      case :ets.whereis(@table_name) do
        :undefined -> start_link()
        _ref -> :ok
      end
    end
  end
end
