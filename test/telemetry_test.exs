defmodule TelemetryTest do
  use ExUnit.Case

  defmodule TestBackfill do
    use AdaptiveBackfill

    batch_operation :with_telemetry, initial_state: 0 do
      mode :sync
      health_checks [fn -> :ok end]
      telemetry_prefix [:test, :backfill]
      
      handle_batch fn
        state when state < 2 -> {:ok, state + 1}
        _ -> :done
      end
    end

    batch_operation :with_success_callback, initial_state: 0 do
      mode :sync
      health_checks [fn -> :ok end]
      
      handle_batch fn
        state when state < 3 -> {:ok, state + 1}
        _ -> :done
      end
      
      on_success fn state ->
        send(self(), {:success, state})
      end
    end

    batch_operation :with_all_callbacks, initial_state: 0 do
      mode :sync
      health_checks [fn -> :ok end]
      telemetry_prefix [:test, :full]
      
      handle_batch fn
        0 -> {:ok, 1}
        1 -> {:error, :test_error}
        _ -> :done
      end
      
      on_success fn state ->
        send(self(), {:on_success, state})
      end
      
      on_error fn error, state ->
        send(self(), {:on_error, error, state})
      end
      
      on_complete fn result ->
        send(self(), {:on_complete, result})
      end
    end
  end

  describe "telemetry events" do
    test "emits start and stop events" do
      events = capture_telemetry_events([:test, :backfill], fn ->
        TestBackfill.with_telemetry()
      end)

      event_names = Enum.map(events, fn {name, _, _} -> name end)
      
      assert [:test, :backfill, :start] in event_names
      assert [:test, :backfill, :stop] in event_names
    end

    test "emits batch events for each batch" do
      events = capture_telemetry_events([:test, :backfill], fn ->
        TestBackfill.with_telemetry()
      end)

      batch_events = Enum.filter(events, fn {name, _, _} ->
        List.starts_with?(name, [:test, :backfill, :batch])
      end)

      # Should have start, success, and done events for batches
      assert length(batch_events) > 0
    end

    test "includes measurements in events" do
      events = capture_telemetry_events([:test, :backfill], fn ->
        TestBackfill.with_telemetry()
      end)

      stop_event = Enum.find(events, fn {name, _, _} ->
        name == [:test, :backfill, :stop]
      end)

      assert {_, measurements, _} = stop_event
      assert Map.has_key?(measurements, :duration)
      assert is_integer(measurements.duration)
    end

    test "includes metadata in events" do
      events = capture_telemetry_events([:test, :backfill], fn ->
        TestBackfill.with_telemetry()
      end)

      start_event = Enum.find(events, fn {name, _, _} ->
        name == [:test, :backfill, :start]
      end)

      assert {_, _, metadata} = start_event
      assert metadata.mode == :sync
    end
  end

  describe "on_success callback" do
    test "calls on_success after each successful batch" do
      assert {:ok, :done} = TestBackfill.with_success_callback()
      
      # Should receive success for states 1, 2, 3
      assert_receive {:success, 1}
      assert_receive {:success, 2}
      assert_receive {:success, 3}
    end

    test "can override on_success at runtime" do
      custom_success = fn state ->
        send(self(), {:custom_success, state})
      end
      
      assert {:ok, :done} = TestBackfill.with_success_callback(on_success: custom_success)
      
      assert_receive {:custom_success, 1}
      assert_receive {:custom_success, 2}
      assert_receive {:custom_success, 3}
      refute_receive {:success, _}
    end
  end

  describe "combined callbacks" do
    test "on_success is called before error" do
      events = capture_telemetry_events([:test, :full], fn ->
        TestBackfill.with_all_callbacks()
      end)
      
      # First batch succeeds
      assert_receive {:on_success, 1}
      
      # Second batch fails
      assert_receive {:on_error, :test_error, 1}
      
      # on_complete not called because of error
      refute_receive {:on_complete, _}
      
      # Should have telemetry events
      assert length(events) > 0
    end
  end

  describe "telemetry without prefix" do
    defmodule NoTelemetryBackfill do
      use AdaptiveBackfill

      batch_operation :no_telemetry, initial_state: 0 do
        mode :sync
        health_checks [fn -> :ok end]
        
        handle_batch fn
          0 -> {:ok, 1}
          _ -> :done
        end
      end
    end

    test "works without telemetry prefix" do
      # Should not crash when telemetry_prefix is nil
      assert {:ok, :done} = NoTelemetryBackfill.no_telemetry()
    end
  end

  # Helper to capture telemetry events
  defp capture_telemetry_events(prefix, fun) do
    test_pid = self()
    ref = make_ref()
    
    handler_id = {:telemetry_test, ref}
    
    :telemetry.attach_many(
      handler_id,
      [
        prefix ++ [:start],
        prefix ++ [:stop],
        prefix ++ [:batch, :start],
        prefix ++ [:batch, :success],
        prefix ++ [:batch, :done],
        prefix ++ [:batch, :error],
        prefix ++ [:health_check, :halt]
      ],
      fn event_name, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, ref, event_name, measurements, metadata})
      end,
      nil
    )
    
    fun.()
    
    :telemetry.detach(handler_id)
    
    collect_telemetry_events(ref, [])
  end
  
  defp collect_telemetry_events(ref, acc) do
    receive do
      {:telemetry_event, ^ref, name, measurements, metadata} ->
        collect_telemetry_events(ref, [{name, measurements, metadata} | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end
end
