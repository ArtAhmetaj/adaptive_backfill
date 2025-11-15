defmodule SingleOperationProcessor do
  @moduledoc """
  Processes single operations with health checks. The user controls the operations and has a health_check callback to handle the check imperatively.
  """
  alias MonitorResultEvaluator
  alias SingleOperationOptions

  def process(%SingleOperationOptions{} = options) do
    %{
      handle: handle,
      on_complete: on_complete,
      on_success: on_success,
      on_error: on_error,
      mode: mode,
      health_checkers: health_checkers,
      timeout: timeout,
      telemetry_prefix: telemetry_prefix
    } = options

    start_time = System.monotonic_time()
    emit_telemetry(telemetry_prefix, [:start], %{}, %{mode: mode})

    health_cb = build_health_check_callback(mode, health_checkers)

    try do
      operation_result =
        if timeout do
          Task.async(fn -> handle.(health_cb) end)
          |> Task.await(timeout)
        else
          handle.(health_cb)
        end

      duration = System.monotonic_time() - start_time

      case operation_result do
        :done ->
          emit_telemetry(telemetry_prefix, [:success], %{duration: duration}, %{mode: mode})
          if on_success, do: on_success.(:done)
          if on_complete, do: on_complete.(:done)
          {:ok, :done}

        {:ok, state} ->
          emit_telemetry(telemetry_prefix, [:success], %{state: state, duration: duration}, %{
            mode: mode
          })

          if on_success, do: on_success.(state)
          if on_complete, do: on_complete.(state)
          {:ok, state}

        {:halt, state} ->
          emit_telemetry(telemetry_prefix, [:halt], %{state: state, duration: duration}, %{
            mode: mode
          })

          if on_complete, do: on_complete.(state)
          {:halt, state}

        {:error, reason} = err ->
          emit_telemetry(telemetry_prefix, [:error], %{error: reason, duration: duration}, %{
            mode: mode
          })

          if on_error, do: on_error.(reason)
          err
      end
    rescue
      error ->
        duration = System.monotonic_time() - start_time

        emit_telemetry(telemetry_prefix, [:exception], %{error: error, duration: duration}, %{
          mode: mode
        })

        if on_error, do: on_error.(error)
        {:error, error}
    catch
      :exit, reason ->
        duration = System.monotonic_time() - start_time

        emit_telemetry(telemetry_prefix, [:exit], %{reason: reason, duration: duration}, %{
          mode: mode
        })

        if on_error, do: on_error.({:exit, reason})
        {:error, {:exit, reason}}
    end
  end

  defp build_health_check_callback(:async, health_checkers) do
    {:ok, pid} = AsyncMonitor.start_link(health_checkers)

    fn ->
      monitor_results = AsyncMonitor.get_state(pid)

      if MonitorResultEvaluator.halt?(monitor_results) do
        {:halt, monitor_results}
      else
        :ok
      end
    end
  end

  defp build_health_check_callback(:sync, health_checkers) do
    fn ->
      monitor_results = SyncMonitor.get_state(health_checkers)

      if MonitorResultEvaluator.halt?(monitor_results) do
        {:halt, monitor_results}
      else
        :ok
      end
    end
  end

  defp emit_telemetry(nil, _event, _measurements, _metadata), do: :ok

  defp emit_telemetry(prefix, event, measurements, metadata) do
    :telemetry.execute(prefix ++ event, measurements, metadata)
  end
end
