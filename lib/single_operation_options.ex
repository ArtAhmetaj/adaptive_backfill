defmodule SingleOperationOptions do
  @moduledoc """
  Struct that holds single operation options, this is for the user to control and not batch.
  """

  alias Types

  @type health_check :: (-> :ok | {:halt, any()})

  @type t :: %__MODULE__{
          handle: (health_check() -> {:ok, any()} | {:error, any()} | {:halt, any()}),
          on_complete: (any() -> any()),
          mode: Types.operation_mode(),
          health_checkers: [Types.health_checker()]
        }

  defstruct [:handle, :on_complete, :mode, :health_checkers]


  def new(handle, on_complete, mode, health_checkers) do
    cond do
      is_nil(handle) ->
        {:error, :invalid_handle}

      invalid_on_complete?(on_complete) ->
        {:error, :invalid_on_complete}

      invalid_mode?(mode) ->
        {:error, :invalid_mode}

      invalid_health_checkers?(health_checkers) ->
        {:error, :invalid_health_checkers}

      true ->
        {:ok,
         %__MODULE__{
           handle: handle,
           on_complete: on_complete,
           mode: mode,
           health_checkers: health_checkers
         }}
    end
  end

  defp invalid_on_complete?(func), do: not is_function(func, 1)

  defp invalid_mode?(:sync),  do: false
  defp invalid_mode?(:async), do: false
  defp invalid_mode?(_),      do: true

  defp invalid_health_checkers?(nil), do: true
  defp invalid_health_checkers?([]),  do: true

  defp invalid_health_checkers?(checks),
    do: not Enum.all?(checks, &is_function(&1, 0))
end
