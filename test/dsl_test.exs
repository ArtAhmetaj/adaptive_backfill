defmodule DSLTest do
  use ExUnit.Case

  defmodule TestBackfill do
    use AdaptiveBackfill

    single_operation :simple_operation do
      mode :sync
      health_checks [fn -> :ok end]
      
      handle fn _health_check ->
        :done
      end
    end

    single_operation :operation_with_callback do
      mode :sync
      health_checks [fn -> :ok end]
      
      handle fn health_check ->
        case health_check.() do
          :ok -> {:ok, :completed}
          {:halt, reason} -> {:halt, reason}
        end
      end
      
      on_complete fn result ->
        send(self(), {:completed, result})
      end
    end

    batch_operation :simple_batch, initial_state: 0 do
      mode :sync
      health_checks [fn -> :ok end]
      
      handle_batch fn
        state when state < 3 -> {:ok, state + 1}
        _ -> :done
      end
    end

    batch_operation :batch_with_callback, initial_state: 0 do
      mode :async
      health_checks [fn -> :ok end]
      
      handle_batch fn state ->
        if state < 2, do: {:ok, state + 1}, else: :done
      end
      
      on_complete fn result ->
        send(self(), {:batch_completed, result})
      end
    end
  end

  describe "single_operation DSL" do
    test "simple operation works" do
      assert {:ok, :done} = TestBackfill.simple_operation()
    end

    test "operation with callback" do
      assert {:ok, :completed} = TestBackfill.operation_with_callback()
      assert_receive {:completed, :completed}
    end

    test "can override options at runtime" do
      custom_handle = fn _health_check -> {:ok, :custom_result} end
      assert {:ok, :custom_result} = TestBackfill.simple_operation(handle: custom_handle)
    end

    test "health check failure halts operation" do
      failing_health = [fn -> {:halt, :unhealthy} end]
      
      handle = fn health_check ->
        case health_check.() do
          :ok -> :done
          {:halt, reason} -> {:halt, reason}
        end
      end
      
      result = TestBackfill.simple_operation(health_checks: failing_health, handle: handle)
      assert match?({:halt, _}, result)
    end
  end

  describe "batch_operation DSL" do
    test "simple batch works" do
      assert {:ok, :done} = TestBackfill.simple_batch()
    end

    test "batch with callback" do
      assert {:ok, :done} = TestBackfill.batch_with_callback()
      assert_receive {:batch_completed, :done}
    end

    test "can override initial_state at runtime" do
      assert {:ok, :done} = TestBackfill.simple_batch(initial_state: 2)
    end

    test "health check failure halts batch" do
      failing_health = [fn -> {:halt, :database_down} end]
      assert {:halt, 1} = TestBackfill.simple_batch(health_checks: failing_health)
    end
  end

  describe "__backfills__ introspection" do
    test "lists all defined backfills" do
      backfills = TestBackfill.__backfills__()
      
      assert {:single, :simple_operation} in backfills
      assert {:single, :operation_with_callback} in backfills
      assert {:batch, :simple_batch} in backfills
      assert {:batch, :batch_with_callback} in backfills
    end
  end
end
