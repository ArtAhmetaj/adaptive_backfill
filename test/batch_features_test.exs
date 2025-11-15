defmodule BatchFeaturesTest do
  use ExUnit.Case

  defmodule TestBackfill do
    use AdaptiveBackfill

    batch_operation :with_delay, initial_state: 0 do
      mode :sync
      health_checks [fn -> :ok end]
      delay_between_batches 100
      
      handle_batch fn
        state when state < 3 -> {:ok, state + 1}
        _ -> :done
      end
    end

    batch_operation :with_timeout, initial_state: 0 do
      mode :sync
      health_checks [fn -> :ok end]
      timeout 1000
      
      handle_batch fn
        0 -> {:ok, 1}
        _ -> :done
      end
    end

    batch_operation :with_error_callback, initial_state: 0 do
      mode :sync
      health_checks [fn -> :ok end]
      
      handle_batch fn
        0 -> {:error, :test_error}
        _ -> :done
      end
      
      on_error fn error, state ->
        send(self(), {:error_caught, error, state})
      end
    end

    batch_operation :with_all_features, initial_state: 0 do
      mode :sync
      health_checks [fn -> :ok end]
      delay_between_batches 50
      timeout 5000
      batch_size 10
      
      handle_batch fn
        state when state < 2 -> {:ok, state + 1}
        _ -> :done
      end
      
      on_complete fn result ->
        send(self(), {:completed, result})
      end
      
      on_error fn error, state ->
        send(self(), {:error, error, state})
      end
    end
  end

  describe "delay_between_batches" do
    test "adds delay between batch executions" do
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, :done} = TestBackfill.with_delay()
      end_time = System.monotonic_time(:millisecond)
      
      # 3 batches with 100ms delay = at least 200ms total (2 delays)
      duration = end_time - start_time
      assert duration >= 200, "Expected at least 200ms, got #{duration}ms"
    end

    test "can override delay at runtime" do
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, :done} = TestBackfill.with_delay(delay_between_batches: 10)
      end_time = System.monotonic_time(:millisecond)
      
      # With 10ms delay, should be much faster
      duration = end_time - start_time
      assert duration < 100, "Expected less than 100ms, got #{duration}ms"
    end
  end

  describe "timeout" do
    test "batch completes within timeout" do
      assert {:ok, :done} = TestBackfill.with_timeout()
    end

    test "can override timeout at runtime" do
      assert {:ok, :done} = TestBackfill.with_timeout(timeout: 2000)
    end
  end

  describe "on_error callback" do
    test "calls on_error when batch returns error" do
      assert {:error, :test_error} = TestBackfill.with_error_callback()
      assert_receive {:error_caught, :test_error, 0}
    end

    test "can override on_error at runtime" do
      custom_error_handler = fn error, state ->
        send(self(), {:custom_error, error, state})
      end
      
      assert {:error, :test_error} = TestBackfill.with_error_callback(on_error: custom_error_handler)
      assert_receive {:custom_error, :test_error, 0}
      refute_receive {:error_caught, _, _}
    end
  end

  describe "batch_size" do
    test "batch_size is informational and doesn't affect execution" do
      # batch_size is just metadata for the user's handle_batch logic
      assert {:ok, :done} = TestBackfill.with_all_features()
    end
  end

  describe "combined features" do
    test "all features work together" do
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, :done} = TestBackfill.with_all_features()
      end_time = System.monotonic_time(:millisecond)
      
      # Should have delay between batches
      duration = end_time - start_time
      assert duration >= 50, "Expected at least 50ms delay"
      
      # Should call on_complete
      assert_receive {:completed, :done}
    end
  end

  describe "error handling with exceptions" do
    defmodule CrashingBackfill do
      use AdaptiveBackfill

      batch_operation :crashes, initial_state: 0 do
        mode :sync
        health_checks [fn -> :ok end]
        
        handle_batch fn
          0 -> raise "Intentional crash"
          _ -> :done
        end
        
        on_error fn error, state ->
          send(self(), {:caught_exception, error, state})
        end
      end
    end

    test "catches exceptions and calls on_error" do
      assert {:error, %RuntimeError{}} = CrashingBackfill.crashes()
      assert_receive {:caught_exception, %RuntimeError{message: "Intentional crash"}, 0}
    end
  end
end
