defmodule BatchOperationProcessorTest do
  use ExUnit.Case

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
end
