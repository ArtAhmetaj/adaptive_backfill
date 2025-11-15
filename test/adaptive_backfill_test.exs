defmodule AdaptiveBackfillTest do
  use ExUnit.Case
  doctest AdaptiveBackfill

  # ============================================================================
  # Basic DSL API Tests
  # ============================================================================

  defmodule ExampleBackfill do
    use AdaptiveBackfill

    single_operation :process_item do
      mode(:sync)
      health_checks([fn -> :ok end])
      handle(fn _health_check -> :done end)
    end

    batch_operation :process_items, initial_state: 0 do
      mode(:sync)
      health_checks([fn -> :ok end])

      handle_batch(fn
        0 -> {:ok, 1}
        1 -> :done
      end)
    end
  end

  describe "DSL API" do
    test "single_operation creates a callable function" do
      assert {:ok, :done} = ExampleBackfill.process_item()
    end

    test "batch_operation creates a callable function" do
      assert {:ok, :done} = ExampleBackfill.process_items()
    end
  end

  describe "Non DSL API" do
    test "run/1 accepts SingleOperationOptions" do
      handle = fn _health_check -> :done end
      {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, [fn -> :ok end])
      result = AdaptiveBackfill.run(opts)
      assert result == {:ok, :done}
    end

    test "run/1 accepts BatchOperationOptions" do
      handle_batch = fn
        0 -> {:ok, 1}
        1 -> :done
      end

      {:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :sync, [fn -> :ok end])
      result = AdaptiveBackfill.run(opts)
      assert result == {:ok, :done}
    end
  end

  # ============================================================================
  # DSL Macro Tests
  # ============================================================================

  describe "DSL macro usage" do
    defmodule FullDSLTest do
      use AdaptiveBackfill

      single_operation :test_single do
        mode(:sync)
        health_checks([fn -> :ok end])
        timeout(5000)
        telemetry_prefix([:test, :single])

        handle(fn _hc -> :done end)

        on_success(fn _result -> :ok end)
        on_error(fn _error -> :ok end)
        on_complete(fn _result -> :ok end)
      end

      batch_operation :test_batch, initial_state: 0 do
        mode(:async)
        health_checks([fn -> :ok end])
        delay_between_batches(100)
        timeout(10_000)
        batch_size(50)
        telemetry_prefix([:test, :batch])

        handle_batch(fn state ->
          if state < 1, do: {:ok, state + 1}, else: :done
        end)

        on_success(fn _state -> :ok end)
        on_error(fn _error, _state -> :ok end)
        on_complete(fn _result -> :ok end)
      end
    end

    test "single_operation macro creates function" do
      assert function_exported?(FullDSLTest, :test_single, 1)
    end

    test "batch_operation macro creates function" do
      assert function_exported?(FullDSLTest, :test_batch, 1)
    end

    test "__backfills__ lists all operations" do
      backfills = FullDSLTest.__backfills__()
      assert {:single, :test_single} in backfills
      assert {:batch, :test_batch} in backfills
    end

    test "single operation executes successfully" do
      assert {:ok, :done} = FullDSLTest.test_single()
    end

    test "batch operation executes successfully" do
      assert {:ok, :done} = FullDSLTest.test_batch()
    end
  end

  describe "DSL macro extraction" do
    test "extract_dsl_config with multiple expressions" do
      block =
        {:__block__, [],
         [
           {:mode, [], [:sync]},
           {:timeout, [], [5000]},
           {:health_checks, [], [[fn -> :ok end]]}
         ]}

      config = AdaptiveBackfill.extract_dsl_config(block)

      assert config[:mode] == :sync
      assert config[:timeout] == 5000
      assert is_list(config[:health_checks])
    end

    test "extract_dsl_config with single expression" do
      expr = {:mode, [], [:async]}
      config = AdaptiveBackfill.extract_dsl_config(expr)

      assert config == %{mode: :async}
    end

    test "extract_dsl_config handles all DSL keywords" do
      block =
        {:__block__, [],
         [
           {:mode, [], [:sync]},
           {:health_checks, [], [[]]},
           {:handle, [], [fn -> :ok end]},
           {:handle_batch, [], [fn _ -> :ok end]},
           {:on_complete, [], [fn _ -> :ok end]},
           {:on_success, [], [fn _ -> :ok end]},
           {:on_error, [], [fn _ -> :ok end]},
           {:delay_between_batches, [], [1000]},
           {:timeout, [], [5000]},
           {:batch_size, [], [100]},
           {:telemetry_prefix, [], [[:test]]}
         ]}

      config = AdaptiveBackfill.extract_dsl_config(block)

      assert Map.has_key?(config, :mode)
      assert Map.has_key?(config, :health_checks)
      assert Map.has_key?(config, :handle)
      assert Map.has_key?(config, :handle_batch)
      assert Map.has_key?(config, :on_complete)
      assert Map.has_key?(config, :on_success)
      assert Map.has_key?(config, :on_error)
      assert Map.has_key?(config, :delay_between_batches)
      assert Map.has_key?(config, :timeout)
      assert Map.has_key?(config, :batch_size)
      assert Map.has_key?(config, :telemetry_prefix)
    end

    test "extract_dsl_config ignores unknown expressions" do
      block =
        {:__block__, [],
         [
           {:mode, [], [:sync]},
           {:unknown_key, [], [:value]},
           {:timeout, [], [5000]}
         ]}

      config = AdaptiveBackfill.extract_dsl_config(block)

      assert config[:mode] == :sync
      assert config[:timeout] == 5000
      refute Map.has_key?(config, :unknown_key)
    end
  end

  # ============================================================================
  # Runtime Override Tests
  # ============================================================================

  describe "runtime option overrides" do
    defmodule OverrideTest do
      use AdaptiveBackfill

      single_operation :override_single do
        mode(:sync)
        health_checks([fn -> :ok end])
        handle(fn _hc -> {:ok, :default} end)
      end

      batch_operation :override_batch, initial_state: 0 do
        mode(:sync)
        health_checks([fn -> :ok end])
        handle_batch(fn _ -> :done end)
      end
    end

    test "can override single operation handle at runtime" do
      custom_handle = fn _hc -> {:ok, :custom} end
      assert {:ok, :custom} = OverrideTest.override_single(handle: custom_handle)
    end

    test "can override single operation mode at runtime" do
      # Just verify it doesn't crash with async mode
      assert {:ok, :default} = OverrideTest.override_single(mode: :async)
    end

    test "can override batch operation initial_state at runtime" do
      custom_batch = fn 99 -> :done end

      assert {:ok, :done} =
               OverrideTest.override_batch(
                 initial_state: 99,
                 handle_batch: custom_batch
               )
    end

    test "can override batch operation mode at runtime" do
      assert {:ok, :done} = OverrideTest.override_batch(mode: :async)
    end
  end

  describe "error handling in DSL" do
    defmodule ErrorHandlingTest do
      use AdaptiveBackfill

      single_operation :invalid_health_checks do
        # Empty health checks should fail
        mode(:sync)
        health_checks([])
        handle(fn _hc -> :done end)
      end
    end

    test "returns error for invalid configuration" do
      assert {:error, :invalid_health_checkers} = ErrorHandlingTest.invalid_health_checks()
    end
  end

  # ============================================================================
  # Edge Cases and Full Coverage
  # ============================================================================

  describe "DSL edge cases and full coverage" do
    defmodule EdgeCaseOps do
      use AdaptiveBackfill

      # Test all single operation options
      single_operation :full_single_op do
        mode(:async)
        health_checks([fn -> :ok end])
        timeout(30_000)
        telemetry_prefix([:edge, :single])

        handle(fn health_check ->
          case health_check.() do
            :ok -> {:ok, :result}
            {:halt, reason} -> {:halt, reason}
          end
        end)

        on_success(fn result -> send(self(), {:success, result}) end)
        on_error(fn error -> send(self(), {:error, error}) end)
        on_complete(fn result -> send(self(), {:complete, result}) end)
      end

      # Test minimal single operation
      single_operation :minimal_single do
        health_checks([fn -> :ok end])
        handle(fn _hc -> :done end)
      end

      # Test all batch operation options
      batch_operation :full_batch_op, initial_state: 0 do
        mode(:async)
        health_checks([fn -> :ok end])
        delay_between_batches(50)
        timeout(10_000)
        batch_size(10)
        telemetry_prefix([:edge, :batch])

        handle_batch(fn
          0 -> {:ok, 1}
          _ -> :done
        end)

        on_success(fn state -> send(self(), {:batch_success, state}) end)
        on_error(fn error, state -> send(self(), {:batch_error, error, state}) end)
        on_complete(fn result -> send(self(), {:batch_complete, result}) end)
      end

      # Test minimal batch operation
      batch_operation :minimal_batch, initial_state: 0 do
        health_checks([fn -> :ok end])
        handle_batch(fn _ -> :done end)
      end

      # Test single operation returning different result types
      single_operation :returns_ok_tuple do
        health_checks([fn -> :ok end])
        handle(fn _hc -> {:ok, %{data: "test"}} end)
      end

      single_operation :returns_halt do
        health_checks([fn -> :ok end])
        handle(fn _hc -> {:halt, :stopped} end)
      end

      single_operation :returns_error do
        health_checks([fn -> :ok end])
        handle(fn _hc -> {:error, :failed} end)
      end

      # Test batch with error
      batch_operation :batch_with_error, initial_state: 0 do
        health_checks([fn -> :ok end])
        handle_batch(fn _ -> {:error, :batch_failed} end)
        on_error(fn error, state -> send(self(), {:caught_error, error, state}) end)
      end
    end

    test "full single operation with all options" do
      assert {:ok, :result} = EdgeCaseOps.full_single_op()
      assert_receive {:success, :result}
      assert_receive {:complete, :result}
    end

    test "minimal single operation with defaults" do
      assert {:ok, :done} = EdgeCaseOps.minimal_single()
    end

    test "full batch operation with all options" do
      assert {:ok, :done} = EdgeCaseOps.full_batch_op()
      assert_receive {:batch_success, 1}
      assert_receive {:batch_complete, :done}
    end

    test "minimal batch operation with defaults" do
      assert {:ok, :done} = EdgeCaseOps.minimal_batch()
    end

    test "single operation returns ok tuple" do
      assert {:ok, %{data: "test"}} = EdgeCaseOps.returns_ok_tuple()
    end

    test "single operation returns halt" do
      assert {:halt, :stopped} = EdgeCaseOps.returns_halt()
    end

    test "single operation returns error" do
      assert {:error, :failed} = EdgeCaseOps.returns_error()
    end

    test "batch operation with error calls on_error" do
      assert {:error, :batch_failed} = EdgeCaseOps.batch_with_error()
      assert_receive {:caught_error, :batch_failed, 0}
    end
  end

  describe "runtime overrides comprehensive" do
    defmodule OverrideOps do
      use AdaptiveBackfill

      single_operation :override_all do
        mode(:sync)
        health_checks([fn -> :ok end])
        timeout(1000)
        telemetry_prefix([:default])
        handle(fn _hc -> {:ok, :default} end)
        on_success(fn _ -> send(self(), :default_success) end)
        on_error(fn _ -> send(self(), :default_error) end)
        on_complete(fn _ -> send(self(), :default_complete) end)
      end

      batch_operation :override_batch_all, initial_state: 0 do
        mode(:sync)
        health_checks([fn -> :ok end])
        delay_between_batches(100)
        timeout(1000)
        batch_size(10)
        telemetry_prefix([:default])
        handle_batch(fn _ -> :done end)
        on_success(fn _ -> send(self(), :default_batch_success) end)
        on_error(fn _, _ -> send(self(), :default_batch_error) end)
        on_complete(fn _ -> send(self(), :default_batch_complete) end)
      end
    end

    test "override all single operation options" do
      custom_handle = fn _hc -> {:ok, :custom} end
      custom_success = fn _ -> send(self(), :custom_success) end
      custom_error = fn _ -> send(self(), :custom_error) end
      custom_complete = fn _ -> send(self(), :custom_complete) end

      assert {:ok, :custom} =
               OverrideOps.override_all(
                 handle: custom_handle,
                 mode: :async,
                 timeout: 5000,
                 telemetry_prefix: [:custom],
                 on_success: custom_success,
                 on_error: custom_error,
                 on_complete: custom_complete
               )

      assert_receive :custom_success
      assert_receive :custom_complete
      refute_received :default_success
      refute_received :default_complete
    end

    test "override all batch operation options" do
      custom_batch = fn 99 -> :done end
      custom_success = fn _ -> send(self(), :custom_batch_success) end
      custom_error = fn _, _ -> send(self(), :custom_batch_error) end
      custom_complete = fn _ -> send(self(), :custom_batch_complete) end

      assert {:ok, :done} =
               OverrideOps.override_batch_all(
                 initial_state: 99,
                 handle_batch: custom_batch,
                 mode: :async,
                 delay_between_batches: 50,
                 timeout: 5000,
                 batch_size: 20,
                 telemetry_prefix: [:custom],
                 on_success: custom_success,
                 on_error: custom_error,
                 on_complete: custom_complete
               )

      assert_receive :custom_batch_complete
      refute_received :default_batch_complete
    end
  end

  # ============================================================================
  # Telemetry Tests
  # ============================================================================

  describe "telemetry events" do
    defmodule TelemetryBackfill do
      use AdaptiveBackfill

      batch_operation :with_telemetry, initial_state: 0 do
        mode(:sync)
        health_checks([fn -> :ok end])
        telemetry_prefix([:test, :backfill])

        handle_batch(fn
          state when state < 2 -> {:ok, state + 1}
          _ -> :done
        end)
      end

      single_operation :single_with_telemetry do
        mode(:sync)
        health_checks([fn -> :ok end])
        telemetry_prefix([:test, :single])
        handle(fn _hc -> :done end)
      end
    end

    test "emits start and stop events for batch" do
      events =
        capture_telemetry_events([:test, :backfill], fn ->
          TelemetryBackfill.with_telemetry()
        end)

      event_names = Enum.map(events, fn {name, _, _} -> name end)

      assert [:test, :backfill, :start] in event_names
      assert [:test, :backfill, :stop] in event_names
    end

    test "emits start and success events for single operation" do
      events =
        capture_telemetry_events([:test, :single], fn ->
          TelemetryBackfill.single_with_telemetry()
        end)

      event_names = Enum.map(events, fn {name, _, _} -> name end)
      assert [:test, :single, :start] in event_names
      assert [:test, :single, :success] in event_names
    end

    test "includes measurements in events" do
      events =
        capture_telemetry_events([:test, :backfill], fn ->
          TelemetryBackfill.with_telemetry()
        end)

      stop_event =
        Enum.find(events, fn {name, _, _} ->
          name == [:test, :backfill, :stop]
        end)

      assert {_, measurements, _} = stop_event
      assert Map.has_key?(measurements, :duration)
      assert is_integer(measurements.duration)
    end

    test "includes metadata in events" do
      events =
        capture_telemetry_events([:test, :backfill], fn ->
          TelemetryBackfill.with_telemetry()
        end)

      start_event =
        Enum.find(events, fn {name, _, _} ->
          name == [:test, :backfill, :start]
        end)

      assert {_, _, metadata} = start_event
      assert metadata.mode == :sync
    end
  end

  describe "telemetry without prefix" do
    defmodule NoTelemetryBackfill do
      use AdaptiveBackfill

      batch_operation :no_telemetry, initial_state: 0 do
        mode(:sync)
        health_checks([fn -> :ok end])

        handle_batch(fn
          0 -> {:ok, 1}
          _ -> :done
        end)
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
        prefix ++ [:success],
        prefix ++ [:halt],
        prefix ++ [:error],
        prefix ++ [:exception],
        prefix ++ [:exit],
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
