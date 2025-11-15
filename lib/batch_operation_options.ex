defmodule BatchOperationOptions do
  @moduledoc """
  Struct that holds config for batch operations, used for pagination or chunked behaviour.
  """

  alias Types

  @type t :: %__MODULE__{
          initial_state: any(),
          handle_batch: (any() -> {:ok, any()} | {:error, any()} | :done),
          on_complete: (any() -> any()),
          on_success: (any() -> any()),
          on_error: (any(), any() -> any()),
          mode: Types.operation_mode(),
          health_checkers: [Types.health_checker()],
          delay_between_batches: non_neg_integer() | nil,
          timeout: non_neg_integer() | nil,
          batch_size: pos_integer() | nil,
          telemetry_prefix: [atom()] | nil
        }

  defstruct [
    :initial_state,
    :handle_batch,
    :on_complete,
    :on_success,
    :on_error,
    :mode,
    :health_checkers,
    :delay_between_batches,
    :timeout,
    :batch_size,
    :telemetry_prefix
  ]

  ##
  ## PUBLIC
  ##

  def new(initial_state, handle_batch, on_complete, mode, health_checkers, opts \\ []) do
    on_success = Keyword.get(opts, :on_success)
    on_error = Keyword.get(opts, :on_error)
    delay_between_batches = Keyword.get(opts, :delay_between_batches)
    timeout = Keyword.get(opts, :timeout)
    batch_size = Keyword.get(opts, :batch_size)
    telemetry_prefix = Keyword.get(opts, :telemetry_prefix)
    cond do
      is_nil(handle_batch) or not is_function(handle_batch, 1) ->
        {:error, :invalid_handle_batch}

      not is_nil(on_complete) and not is_function(on_complete, 1) ->
        {:error, :invalid_on_complete}

      invalid_mode?(mode) ->
        {:error, :invalid_mode}

      invalid_health_checkers?(health_checkers) ->
        {:error, :invalid_health_checkers}

      not is_nil(on_success) and not is_function(on_success, 1) ->
        {:error, :invalid_on_success}

      not is_nil(on_error) and not is_function(on_error, 2) ->
        {:error, :invalid_on_error}

      not is_nil(telemetry_prefix) and not is_list(telemetry_prefix) ->
        {:error, :invalid_telemetry_prefix}

      not is_nil(delay_between_batches) and not is_integer(delay_between_batches) ->
        {:error, :invalid_delay}

      not is_nil(timeout) and not is_integer(timeout) ->
        {:error, :invalid_timeout}

      not is_nil(batch_size) and (not is_integer(batch_size) or batch_size < 1) ->
        {:error, :invalid_batch_size}

      true ->
        {:ok,
         %__MODULE__{
           initial_state: initial_state,
           handle_batch: handle_batch,
           on_complete: on_complete,
           on_success: on_success,
           on_error: on_error,
           mode: mode,
           health_checkers: health_checkers,
           delay_between_batches: delay_between_batches,
           timeout: timeout,
           batch_size: batch_size,
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
