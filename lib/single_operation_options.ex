defmodule SingleOperationOptions do
  @moduledoc """
  Struct that holds single operation options, this is for the user to control and not batch.
  """

  alias Types

  @type health_check :: (-> :ok | {:halt, any()})

  @type t :: %__MODULE__{
          handle: (health_check() -> {:ok, any()} | {:error, any()} | {:halt, any()} | :done),
          on_complete: (any() -> any()),
          on_success: (any() -> any()),
          on_error: (any() -> any()),
          mode: Types.operation_mode(),
          health_checkers: [Types.health_checker()],
          timeout: non_neg_integer() | nil,
          telemetry_prefix: [atom()] | nil
        }

  defstruct [
    :handle,
    :on_complete,
    :on_success,
    :on_error,
    :mode,
    :health_checkers,
    :timeout,
    :telemetry_prefix
  ]

  def new(handle, on_complete, mode, health_checkers, opts \\ []) do
    on_success = Keyword.get(opts, :on_success)
    on_error = Keyword.get(opts, :on_error)
    timeout = Keyword.get(opts, :timeout)
    telemetry_prefix = Keyword.get(opts, :telemetry_prefix)

    cond do
      is_nil(handle) or not is_function(handle, 1) ->
        {:error, :invalid_handle}

      not is_nil(on_complete) and not is_function(on_complete, 1) ->
        {:error, :invalid_on_complete}

      not is_nil(on_success) and not is_function(on_success, 1) ->
        {:error, :invalid_on_success}

      not is_nil(on_error) and not is_function(on_error, 1) ->
        {:error, :invalid_on_error}

      invalid_mode?(mode) ->
        {:error, :invalid_mode}

      invalid_health_checkers?(health_checkers) ->
        {:error, :invalid_health_checkers}

      not is_nil(timeout) and not is_integer(timeout) ->
        {:error, :invalid_timeout}

      not is_nil(telemetry_prefix) and not is_list(telemetry_prefix) ->
        {:error, :invalid_telemetry_prefix}

      true ->
        {:ok,
         %__MODULE__{
           handle: handle,
           on_complete: on_complete,
           on_success: on_success,
           on_error: on_error,
           mode: mode,
           health_checkers: health_checkers,
           timeout: timeout,
           telemetry_prefix: telemetry_prefix
         }}
    end
  end

  defp invalid_mode?(:sync), do: false
  defp invalid_mode?(:async), do: false
  defp invalid_mode?(_), do: true

  defp invalid_health_checkers?(nil), do: true
  defp invalid_health_checkers?([]), do: true

  defp invalid_health_checkers?(checks),
    do: not Enum.all?(checks, &is_function(&1, 0))
end
