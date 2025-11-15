defmodule SingleOperationProcessorTest do
  use ExUnit.Case

  alias AdaptiveBackfill.SingleOperationOptions
  alias AdaptiveBackfill.SingleOperationProcessor

  describe "process/1 with sync mode" do
    test "processes operation that returns :done" do
      handle = fn _health_check -> :done end
      health_checkers = [fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
      assert {:ok, :done} = SingleOperationProcessor.process(opts)
    end

    test "processes operation that returns {:ok, state}" do
      handle = fn _health_check -> {:ok, :my_result} end
      health_checkers = [fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
      assert {:ok, :my_result} = SingleOperationProcessor.process(opts)
    end

    test "processes operation that returns {:halt, state}" do
      handle = fn _health_check -> {:halt, :stopped} end
      health_checkers = [fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
      assert {:halt, :stopped} = SingleOperationProcessor.process(opts)
    end

    test "processes operation that returns {:error, reason}" do
      handle = fn _health_check -> {:error, :failed} end
      health_checkers = [fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
      assert {:error, :failed} = SingleOperationProcessor.process(opts)
    end

    test "calls on_complete when operation returns :done" do
      handle = fn _health_check -> :done end

      on_complete = fn state ->
        :erlang.put(:on_complete_called, state)
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, on_complete, :sync, health_checkers)
      SingleOperationProcessor.process(opts)

      assert :erlang.get(:on_complete_called) == :done
    end

    test "calls on_complete when operation returns {:ok, state}" do
      handle = fn _health_check -> {:ok, :result} end

      on_complete = fn state ->
        :erlang.put(:on_complete_called, state)
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, on_complete, :sync, health_checkers)
      SingleOperationProcessor.process(opts)

      assert :erlang.get(:on_complete_called) == :result
    end

    test "calls on_complete when operation returns {:halt, state}" do
      handle = fn _health_check -> {:halt, :halted} end

      on_complete = fn state ->
        :erlang.put(:on_complete_called, state)
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, on_complete, :sync, health_checkers)
      SingleOperationProcessor.process(opts)

      assert :erlang.get(:on_complete_called) == :halted
    end

    test "does not call on_complete when operation returns error" do
      handle = fn _health_check -> {:error, :failed} end

      on_complete = fn state ->
        :erlang.put(:on_complete_called, state)
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, on_complete, :sync, health_checkers)
      SingleOperationProcessor.process(opts)

      assert :erlang.get(:on_complete_called) == :undefined
    end

    test "health check callback returns :ok when health is good" do
      handle = fn health_check ->
        result = health_check.()
        if result == :ok, do: :done, else: {:halt, result}
      end

      health_checkers = [fn -> :ok end, fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
      assert {:ok, :done} = SingleOperationProcessor.process(opts)
    end

    test "health check callback returns {:halt, results} when health fails" do
      handle = fn health_check ->
        result = health_check.()

        case result do
          :ok -> :done
          {:halt, _} -> {:halt, result}
        end
      end

      health_checkers = [fn -> :ok end, fn -> {:halt, :unhealthy} end]

      {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
      assert {:halt, {:halt, _}} = SingleOperationProcessor.process(opts)
    end

    test "operation can check health multiple times" do
      call_count = :counters.new(1, [])

      handle = fn health_check ->
        result1 = health_check.()
        :counters.add(call_count, 1, 1)

        result2 = health_check.()
        :counters.add(call_count, 1, 1)

        if result1 == :ok and result2 == :ok, do: :done, else: {:halt, :failed}
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
      result = SingleOperationProcessor.process(opts)

      assert {:ok, :done} = result
      assert :counters.get(call_count, 1) == 2
    end

    test "operation can halt itself based on health check" do
      handle = fn health_check ->
        case health_check.() do
          :ok -> {:ok, :continue}
          {:halt, _} -> {:halt, :stopped_due_to_health}
        end
      end

      health_checkers = [fn -> {:halt, :bad_health} end]

      {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
      assert {:halt, :stopped_due_to_health} = SingleOperationProcessor.process(opts)
    end
  end

  describe "process/1 with async mode" do
    test "processes operation with async health checks" do
      handle = fn _health_check -> {:ok, :result} end
      health_checkers = [fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, nil, :async, health_checkers)
      assert {:ok, :result} = SingleOperationProcessor.process(opts)
    end

    test "health check callback works with async mode" do
      handle = fn health_check ->
        result = health_check.()
        if result == :ok, do: :done, else: {:halt, result}
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, nil, :async, health_checkers)
      assert {:ok, :done} = SingleOperationProcessor.process(opts)
    end

    test "async health check can return halt" do
      handle = fn health_check ->
        result = health_check.()

        case result do
          :ok -> :done
          {:halt, _} -> {:halt, result}
        end
      end

      health_checkers = [fn -> {:halt, :async_fail} end]

      {:ok, opts} = SingleOperationOptions.new(handle, nil, :async, health_checkers)
      assert {:halt, {:halt, _}} = SingleOperationProcessor.process(opts)
    end
  end

  describe "error handling" do
    test "catches exceptions in handle function" do
      handle = fn _health_check -> raise "Intentional error" end
      health_checkers = [fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
      assert {:error, %RuntimeError{}} = SingleOperationProcessor.process(opts)
    end

    test "catches exits in handle function" do
      handle = fn _health_check -> exit(:normal) end
      health_checkers = [fn -> :ok end]

      {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
      assert {:error, {:exit, :normal}} = SingleOperationProcessor.process(opts)
    end

    test "calls on_error callback when exception occurs" do
      handle = fn _health_check -> raise "Test error" end

      on_error = fn error ->
        send(self(), {:error_caught, error})
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} =
        SingleOperationOptions.new(handle, nil, :sync, health_checkers, on_error: on_error)

      SingleOperationProcessor.process(opts)
      assert_receive {:error_caught, %RuntimeError{message: "Test error"}}
    end
  end

  describe "callbacks" do
    test "calls on_success callback for successful operations" do
      handle = fn _health_check -> {:ok, :success} end

      on_success = fn result ->
        send(self(), {:success, result})
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} =
        SingleOperationOptions.new(handle, nil, :sync, health_checkers, on_success: on_success)

      SingleOperationProcessor.process(opts)
      assert_receive {:success, :success}
    end

    test "does not call on_success for errors" do
      handle = fn _health_check -> {:error, :failed} end

      on_success = fn result ->
        send(self(), {:success, result})
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} =
        SingleOperationOptions.new(handle, nil, :sync, health_checkers, on_success: on_success)

      SingleOperationProcessor.process(opts)
      refute_receive {:success, _}
    end
  end
end
