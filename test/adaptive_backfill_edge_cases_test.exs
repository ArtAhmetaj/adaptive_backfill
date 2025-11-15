defmodule AdaptiveBackfillEdgeCasesTest do
  use ExUnit.Case

  describe "DSL edge cases and full coverage" do
    defmodule EdgeCaseOps do
      use AdaptiveBackfill

      # Test all single operation options
      single_operation :full_single_op do
        mode :async
        health_checks [fn -> :ok end]
        timeout 30_000
        telemetry_prefix [:edge, :single]
        
        handle fn health_check ->
          case health_check.() do
            :ok -> {:ok, :result}
            {:halt, reason} -> {:halt, reason}
          end
        end
        
        on_success fn result -> send(self(), {:success, result}) end
        on_error fn error -> send(self(), {:error, error}) end
        on_complete fn result -> send(self(), {:complete, result}) end
      end

      # Test minimal single operation
      single_operation :minimal_single do
        health_checks [fn -> :ok end]
        handle fn _hc -> :done end
      end

      # Test all batch operation options
      batch_operation :full_batch_op, initial_state: 0 do
        mode :async
        health_checks [fn -> :ok end]
        delay_between_batches 50
        timeout 10_000
        batch_size 10
        telemetry_prefix [:edge, :batch]
        
        handle_batch fn
          0 -> {:ok, 1}
          _ -> :done
        end
        
        on_success fn state -> send(self(), {:batch_success, state}) end
        on_error fn error, state -> send(self(), {:batch_error, error, state}) end
        on_complete fn result -> send(self(), {:batch_complete, result}) end
      end

      # Test minimal batch operation
      batch_operation :minimal_batch, initial_state: 0 do
        health_checks [fn -> :ok end]
        handle_batch fn _ -> :done end
      end

      # Test single operation returning different result types
      single_operation :returns_ok_tuple do
        health_checks [fn -> :ok end]
        handle fn _hc -> {:ok, %{data: "test"}} end
      end

      single_operation :returns_halt do
        health_checks [fn -> :ok end]
        handle fn _hc -> {:halt, :stopped} end
      end

      single_operation :returns_error do
        health_checks [fn -> :ok end]
        handle fn _hc -> {:error, :failed} end
      end

      # Test batch with error
      batch_operation :batch_with_error, initial_state: 0 do
        health_checks [fn -> :ok end]
        handle_batch fn _ -> {:error, :batch_failed} end
        on_error fn error, state -> send(self(), {:caught_error, error, state}) end
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

  describe "DSL macro helpers" do
    test "mode macro" do
      result = quote do
        AdaptiveBackfill.mode(:sync)
      end
      
      assert result != nil
    end

    test "health_checks macro" do
      result = quote do
        AdaptiveBackfill.health_checks([fn -> :ok end])
      end
      
      assert result != nil
    end

    test "handle macro" do
      result = quote do
        AdaptiveBackfill.handle(fn _ -> :ok end)
      end
      
      assert result != nil
    end

    test "handle_batch macro" do
      result = quote do
        AdaptiveBackfill.handle_batch(fn _ -> :ok end)
      end
      
      assert result != nil
    end

    test "on_complete macro" do
      result = quote do
        AdaptiveBackfill.on_complete(fn _ -> :ok end)
      end
      
      assert result != nil
    end

    test "on_success macro" do
      result = quote do
        AdaptiveBackfill.on_success(fn _ -> :ok end)
      end
      
      assert result != nil
    end

    test "on_error macro" do
      result = quote do
        AdaptiveBackfill.on_error(fn _ -> :ok end)
      end
      
      assert result != nil
    end

    test "delay_between_batches macro" do
      result = quote do
        AdaptiveBackfill.delay_between_batches(1000)
      end
      
      assert result != nil
    end

    test "timeout macro" do
      result = quote do
        AdaptiveBackfill.timeout(5000)
      end
      
      assert result != nil
    end

    test "batch_size macro" do
      result = quote do
        AdaptiveBackfill.batch_size(100)
      end
      
      assert result != nil
    end

    test "telemetry_prefix macro" do
      result = quote do
        AdaptiveBackfill.telemetry_prefix([:test])
      end
      
      assert result != nil
    end
  end

  describe "runtime overrides comprehensive" do
    defmodule OverrideOps do
      use AdaptiveBackfill

      single_operation :override_all do
        mode :sync
        health_checks [fn -> :ok end]
        timeout 1000
        telemetry_prefix [:default]
        handle fn _hc -> {:ok, :default} end
        on_success fn _ -> send(self(), :default_success) end
        on_error fn _ -> send(self(), :default_error) end
        on_complete fn _ -> send(self(), :default_complete) end
      end

      batch_operation :override_batch_all, initial_state: 0 do
        mode :sync
        health_checks [fn -> :ok end]
        delay_between_batches 100
        timeout 1000
        batch_size 10
        telemetry_prefix [:default]
        handle_batch fn _ -> :done end
        on_success fn _ -> send(self(), :default_batch_success) end
        on_error fn _, _ -> send(self(), :default_batch_error) end
        on_complete fn _ -> send(self(), :default_batch_complete) end
      end
    end

    test "override all single operation options" do
      custom_handle = fn _hc -> {:ok, :custom} end
      custom_success = fn _ -> send(self(), :custom_success) end
      custom_error = fn _ -> send(self(), :custom_error) end
      custom_complete = fn _ -> send(self(), :custom_complete) end
      
      assert {:ok, :custom} = OverrideOps.override_all(
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
      
      assert {:ok, :done} = OverrideOps.override_batch_all(
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
end
