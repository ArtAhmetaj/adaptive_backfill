defmodule AdaptiveBackfillDSLTest do
  use ExUnit.Case

  describe "DSL macro usage" do
    defmodule FullDSLTest do
      use AdaptiveBackfill

      single_operation :test_single do
        mode :sync
        health_checks [fn -> :ok end]
        timeout 5000
        telemetry_prefix [:test, :single]
        
        handle fn _hc -> :done end
        
        on_success fn _result -> :ok end
        on_error fn _error -> :ok end
        on_complete fn _result -> :ok end
      end

      batch_operation :test_batch, initial_state: 0 do
        mode :async
        health_checks [fn -> :ok end]
        delay_between_batches 100
        timeout 10_000
        batch_size 50
        telemetry_prefix [:test, :batch]
        
        handle_batch fn state ->
          if state < 1, do: {:ok, state + 1}, else: :done
        end
        
        on_success fn _state -> :ok end
        on_error fn _error, _state -> :ok end
        on_complete fn _result -> :ok end
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
      block = {:__block__, [], [
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
      block = {:__block__, [], [
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
      block = {:__block__, [], [
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

  describe "legacy API" do
    test "run/1 with SingleOperationOptions" do
      handle = fn _hc -> :done end
      {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, [fn -> :ok end])
      
      assert {:ok, :done} = AdaptiveBackfill.run(opts)
    end

    test "run/1 with BatchOperationOptions" do
      handle_batch = fn 0 -> :done end
      {:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :sync, [fn -> :ok end])
      
      assert {:ok, :done} = AdaptiveBackfill.run(opts)
    end
  end

  describe "runtime option overrides" do
    defmodule OverrideTest do
      use AdaptiveBackfill

      single_operation :override_single do
        mode :sync
        health_checks [fn -> :ok end]
        handle fn _hc -> {:ok, :default} end
      end

      batch_operation :override_batch, initial_state: 0 do
        mode :sync
        health_checks [fn -> :ok end]
        handle_batch fn _ -> :done end
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
      assert {:ok, :done} = OverrideTest.override_batch(
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
        mode :sync
        health_checks []  # Empty health checks should fail
        handle fn _hc -> :done end
      end
    end

    test "returns error for invalid configuration" do
      assert {:error, :invalid_health_checkers} = ErrorHandlingTest.invalid_health_checks()
    end
  end
end
