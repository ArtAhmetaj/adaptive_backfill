defmodule BatchOperationProcessor do
  @moduledoc """
  Processes batches of operations with health checks. The library handles the health checks by batches and the user does not control the process.
  """
  alias BatchOperationOptions
  alias MonitorResultEvaluator

  def process(%BatchOperationOptions{} = options) do
    %{
      initial_state: initial_state,
      handle_batch: handle_batch,
      on_complete: on_complete,
      on_success: on_success,
      on_error: on_error,
      mode: mode,
      health_checkers: health_checkers,
      delay_between_batches: delay,
      timeout: timeout,
      telemetry_prefix: telemetry_prefix,
      checkpoint: checkpoint
    } = options

    # Try to load checkpoint
    starting_state = load_checkpoint(checkpoint, initial_state)

    start_time = System.monotonic_time()

    emit_telemetry(telemetry_prefix, [:start], %{initial_state: starting_state}, %{
      mode: mode,
      resumed: starting_state != initial_state
    })

    health_check_context = init_health_checks(mode, health_checkers)

    result =
      run_batch_cycle(
        starting_state,
        handle_batch,
        on_complete,
        on_success,
        on_error,
        mode,
        health_check_context,
        delay,
        timeout,
        telemetry_prefix,
        checkpoint,
        0
      )

    cleanup_health_checks(mode, health_check_context)

    # Clear checkpoint on successful completion
    case result do
      {:ok, :done} -> Checkpoint.delete(checkpoint)
      # Keep checkpoint for manual resume
      {:halt, _} -> :ok
      # Keep checkpoint for retry
      {:error, _} -> :ok
    end

    duration = System.monotonic_time() - start_time

    emit_telemetry(telemetry_prefix, [:stop], %{result: result, duration: duration}, %{mode: mode})

    result
  end

  defp load_checkpoint(nil, initial_state), do: initial_state

  defp load_checkpoint(checkpoint, initial_state) do
    case Checkpoint.load(checkpoint) do
      {:ok, state} -> state
      {:error, :not_found} -> initial_state
      {:error, _} -> initial_state
    end
  end

  def run_batch_cycle(
        state,
        handle_batch,
        on_complete,
        on_success,
        on_error,
        mode,
        health_check_context,
        delay,
        timeout,
        telemetry_prefix,
        checkpoint,
        batch_count
      ) do
    batch_start = System.monotonic_time()

    emit_telemetry(
      telemetry_prefix,
      [:batch, :start],
      %{state: state, batch_count: batch_count},
      %{mode: mode}
    )

    try do
      batch_result =
        if timeout do
          Task.async(fn -> handle_batch.(state) end)
          |> Task.await(timeout)
        else
          handle_batch.(state)
        end

      batch_duration = System.monotonic_time() - batch_start

      case batch_result do
        :done ->
          emit_telemetry(
            telemetry_prefix,
            [:batch, :done],
            %{state: state, duration: batch_duration, batch_count: batch_count},
            %{mode: mode}
          )

          if on_complete, do: on_complete.(:done)
          {:ok, :done}

        {:ok, next_state} ->
          emit_telemetry(
            telemetry_prefix,
            [:batch, :success],
            %{
              state: state,
              next_state: next_state,
              duration: batch_duration,
              batch_count: batch_count
            },
            %{mode: mode}
          )

          if on_success, do: on_success.(next_state)

          # Save checkpoint after successful batch
          Checkpoint.save(checkpoint, next_state)

          if delay, do: Process.sleep(delay)

          monitor_results = run_health_checks(mode, health_check_context)

          if MonitorResultEvaluator.halt?(monitor_results) do
            emit_telemetry(
              telemetry_prefix,
              [:health_check, :halt],
              %{state: next_state, results: monitor_results},
              %{mode: mode}
            )

            if on_complete, do: on_complete.(next_state)
            {:halt, next_state}
          else
            run_batch_cycle(
              next_state,
              handle_batch,
              on_complete,
              on_success,
              on_error,
              mode,
              health_check_context,
              delay,
              timeout,
              telemetry_prefix,
              checkpoint,
              batch_count + 1
            )
          end

        {:error, reason} = err ->
          emit_telemetry(
            telemetry_prefix,
            [:batch, :error],
            %{state: state, error: reason, duration: batch_duration, batch_count: batch_count},
            %{mode: mode}
          )

          # Save checkpoint on error so we can resume
          Checkpoint.save(checkpoint, state)
          if on_error, do: on_error.(reason, state)
          err
      end
    rescue
      error ->
        batch_duration = System.monotonic_time() - batch_start

        emit_telemetry(
          telemetry_prefix,
          [:batch, :exception],
          %{state: state, error: error, duration: batch_duration, batch_count: batch_count},
          %{mode: mode}
        )

        # Save checkpoint on exception
        Checkpoint.save(checkpoint, state)
        if on_error, do: on_error.(error, state)
        {:error, error}
    catch
      :exit, reason ->
        batch_duration = System.monotonic_time() - batch_start

        emit_telemetry(
          telemetry_prefix,
          [:batch, :exit],
          %{state: state, reason: reason, duration: batch_duration, batch_count: batch_count},
          %{mode: mode}
        )

        # Save checkpoint on exit
        Checkpoint.save(checkpoint, state)
        if on_error, do: on_error.({:exit, reason}, state)
        {:error, {:exit, reason}}
    end
  end

  defp init_health_checks(:async, health_checkers) do
    {:ok, pid} = AsyncMonitor.start_link(health_checkers)
    pid
  end

  defp init_health_checks(:sync, health_checkers) do
    health_checkers
  end

  defp run_health_checks(:async, pid) do
    GenServer.call(pid, :get_state)
  end

  defp run_health_checks(:sync, health_checkers) do
    SyncMonitor.get_state(health_checkers)
  end

  defp cleanup_health_checks(:async, pid) do
    GenServer.stop(pid)
  end

  defp cleanup_health_checks(:sync, _health_checkers) do
    :ok
  end

  defp emit_telemetry(nil, _event, _measurements, _metadata), do: :ok

  defp emit_telemetry(prefix, event, measurements, metadata) do
    :telemetry.execute(prefix ++ event, measurements, metadata)
  end
end
