defmodule BatchOperationProcessorTest do
  use ExUnit.Case

  alias AdaptiveBackfill.BatchOperationOptions
  alias AdaptiveBackfill.BatchOperationProcessor

  describe "process/1 with sync mode" do
    test "processes batches until done is returned" do
      handle_batch = fn
        0 -> {:ok, 1}
        1 -> {:ok, 2}
        2 -> :done
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers)
      assert {:ok, :done} = BatchOperationProcessor.process(opts)
    end

    test "calls on_complete when done" do
      handle_batch = fn state -> if state < 2, do: {:ok, state + 1}, else: :done end

      on_complete = fn state ->
        :erlang.put(:on_complete_called, state)
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} =
        BatchOperationOptions.new(0, handle_batch, on_complete, :sync, health_checkers)

      BatchOperationProcessor.process(opts)

      assert :erlang.get(:on_complete_called) == :done
    end

    test "halts when health check returns halt" do
      handle_batch = fn state -> {:ok, state + 1} end

      health_checkers = [
        fn -> :ok end,
        fn -> {:halt, :unhealthy} end
      ]

      {:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers)
      assert {:halt, 1} = BatchOperationProcessor.process(opts)
    end

    test "calls on_complete when halted" do
      handle_batch = fn state -> {:ok, state + 1} end

      on_complete = fn state ->
        :erlang.put(:on_complete_called, state)
      end

      health_checkers = [fn -> {:halt, :stop} end]

      {:ok, opts} =
        BatchOperationOptions.new(0, handle_batch, on_complete, :sync, health_checkers)

      BatchOperationProcessor.process(opts)

      assert :erlang.get(:on_complete_called) == 1
    end

    test "returns error when handle_batch returns error" do
      handle_batch = fn
        0 -> {:ok, 1}
        1 -> {:error, :something_went_wrong}
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers)
      assert {:error, :something_went_wrong} = BatchOperationProcessor.process(opts)
    end

    test "processes multiple batches with healthy checks" do
      handle_batch = fn
        state when state < 5 -> {:ok, state + 1}
        5 -> :done
      end

      health_checkers = [fn -> :ok end, fn -> :ok end]

      {:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers)
      assert {:ok, :done} = BatchOperationProcessor.process(opts)
    end

    test "halts on second batch when health check fails" do
      handle_batch = fn state -> {:ok, state + 1} end
      call_count = :counters.new(1, [])

      health_checkers = [
        fn ->
          count = :counters.get(call_count, 1)
          :counters.add(call_count, 1, 1)
          if count >= 1, do: {:halt, :failed}, else: :ok
        end
      ]

      {:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers)
      assert {:halt, 2} = BatchOperationProcessor.process(opts)
    end
  end

  describe "process/1 with async mode" do
    test "processes batches until done with async health checks" do
      handle_batch = fn
        0 -> {:ok, 1}
        1 -> {:ok, 2}
        2 -> :done
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :async, health_checkers)
      assert {:ok, :done} = BatchOperationProcessor.process(opts)
    end

    test "halts when async health check returns halt" do
      handle_batch = fn state -> {:ok, state + 1} end
      health_checkers = [fn -> {:halt, :async_unhealthy} end]

      {:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :async, health_checkers)
      assert {:halt, 1} = BatchOperationProcessor.process(opts)
    end
  end

  describe "delay_between_batches" do
    test "adds delay between batch executions" do
      handle_batch = fn
        state when state < 3 -> {:ok, state + 1}
        _ -> :done
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} =
        BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers,
          delay_between_batches: 100
        )

      start_time = System.monotonic_time(:millisecond)
      BatchOperationProcessor.process(opts)
      end_time = System.monotonic_time(:millisecond)

      # 3 batches with 100ms delay = at least 200ms total (2 delays)
      duration = end_time - start_time
      assert duration >= 200, "Expected at least 200ms, got #{duration}ms"
    end
  end

  describe "error handling" do
    test "catches exceptions in handle_batch" do
      handle_batch = fn
        0 -> raise "Intentional crash"
        _ -> :done
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers)
      assert {:error, %RuntimeError{}} = BatchOperationProcessor.process(opts)
    end

    test "calls on_error callback when exception occurs" do
      handle_batch = fn
        0 -> raise "Test error"
        _ -> :done
      end

      on_error = fn error, state ->
        send(self(), {:caught_exception, error, state})
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} =
        BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers,
          on_error: on_error
        )

      BatchOperationProcessor.process(opts)
      assert_receive {:caught_exception, %RuntimeError{message: "Test error"}, 0}
    end

    test "calls on_error when handle_batch returns error" do
      handle_batch = fn
        0 -> {:error, :test_error}
        _ -> :done
      end

      on_error = fn error, state ->
        send(self(), {:error_caught, error, state})
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} =
        BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers,
          on_error: on_error
        )

      BatchOperationProcessor.process(opts)
      assert_receive {:error_caught, :test_error, 0}
    end
  end

  describe "callbacks" do
    test "calls on_success after each successful batch" do
      handle_batch = fn
        state when state < 3 -> {:ok, state + 1}
        _ -> :done
      end

      on_success = fn state ->
        send(self(), {:success, state})
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} =
        BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers,
          on_success: on_success
        )

      BatchOperationProcessor.process(opts)

      # Should receive success for states 1, 2, 3
      assert_receive {:success, 1}
      assert_receive {:success, 2}
      assert_receive {:success, 3}
    end

    test "does not call on_success when batch returns error" do
      handle_batch = fn
        0 -> {:ok, 1}
        1 -> {:error, :failed}
        _ -> :done
      end

      on_success = fn state ->
        send(self(), {:success, state})
      end

      health_checkers = [fn -> :ok end]

      {:ok, opts} =
        BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers,
          on_success: on_success
        )

      BatchOperationProcessor.process(opts)

      # Should only receive success for state 1
      assert_receive {:success, 1}
      refute_receive {:success, _}
    end
  end
end
