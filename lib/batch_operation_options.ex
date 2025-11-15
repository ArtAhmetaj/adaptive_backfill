defmodule BatchOperationOptions do
  @moduledoc """
  Struct that holds config for batch operations, used for pagination or chunked behaviour.
  """

  alias Types

  @type t :: %__MODULE__{
          initial_state: any(),
          handle_batch: (any() -> any()),
          on_complete: (any() -> any()),
          mode: Types.operation_mode(),
          health_checkers: [Types.health_checker()]
        }

  defstruct [:initial_state, :handle_batch, :on_complete, :mode, :health_checkers]

  ##
  ## PUBLIC
  ##

  def new(initial_state, handle_batch, on_complete, mode, health_checkers) do
    cond do
      is_nil(handle_batch) or invalid_handle_batch?(handle_batch) ->
        {:error, :invalid_handle_batch}

      is_nil(on_complete) or invalid_on_complete?(on_complete) ->
        {:error, :invalid_on_complete}

      invalid_mode?(mode) ->
        {:error, :invalid_mode}

      invalid_health_checkers?(health_checkers) ->
        {:error, :invalid_health_checkers}

      true ->
        {:ok,
         %__MODULE__{
           initial_state: initial_state,
           handle_batch: handle_batch,
           on_complete: on_complete,
           mode: mode,
           health_checkers: health_checkers
         }}
    end
  end

  ##
  ## VALIDATION HELPERS
  ##

  defp invalid_handle_batch?(func), do: not is_function(func, 1)
  defp invalid_on_complete?(func), do: not is_function(func, 1)

  defp invalid_mode?(:sync),  do: false
  defp invalid_mode?(:async), do: false
  defp invalid_mode?(_),      do: true

  defp invalid_health_checkers?(nil), do: true
  defp invalid_health_checkers?([]),  do: true

  defp invalid_health_checkers?(checks),
    do: not Enum.all?(checks, &is_function(&1, 0))
end
