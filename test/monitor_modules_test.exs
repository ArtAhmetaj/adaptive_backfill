defmodule MonitorModulesTest do
  use ExUnit.Case

  describe "AsyncBackfillMonitor" do
    test "starts with initial state" do
      initial_state = %{count: 0}
      {:ok, pid} = AsyncBackfillMonitor.start_link(initial_state)

      state = AsyncBackfillMonitor.get_monitored_state()
      assert state == %{state: initial_state}

      GenServer.stop(pid)
    end

    test "returns state on get_monitored_state" do
      state = %{status: :healthy}
      {:ok, pid} = AsyncBackfillMonitor.start_link(state)

      result = AsyncBackfillMonitor.get_monitored_state()
      assert result == %{state: state}

      GenServer.stop(pid)
    end

    test "handles unknown operations" do
      {:ok, pid} = AsyncBackfillMonitor.start_link(%{})

      result = GenServer.call(pid, :unknown_operation)
      assert result == {:error, :unknown_operation}

      GenServer.stop(pid)
    end

    test "maintains state across multiple calls" do
      initial = %{counter: 42}
      {:ok, pid} = AsyncBackfillMonitor.start_link(initial)

      state1 = AsyncBackfillMonitor.get_monitored_state()
      state2 = AsyncBackfillMonitor.get_monitored_state()

      assert state1 == state2
      assert state1 == %{state: initial}

      GenServer.stop(pid)
    end
  end

  describe "SyncBackfillMonitor" do
    test "executes function and returns result" do
      func = fn -> {:ok, :result} end
      assert SyncBackfillMonitor.monitor(func) == {:ok, :result}
    end

    test "passes through function return value" do
      func = fn -> :done end
      assert SyncBackfillMonitor.monitor(func) == :done
    end

    test "handles functions that return tuples" do
      func = fn -> {:error, :something_wrong} end
      assert SyncBackfillMonitor.monitor(func) == {:error, :something_wrong}
    end

    test "handles functions that return complex data" do
      func = fn -> %{status: :ok, data: [1, 2, 3]} end
      assert SyncBackfillMonitor.monitor(func) == %{status: :ok, data: [1, 2, 3]}
    end

    test "executes function side effects" do
      test_pid = self()

      func = fn ->
        send(test_pid, :executed)
        :ok
      end

      SyncBackfillMonitor.monitor(func)
      assert_receive :executed
    end
  end

  describe "SyncMonitor" do
    test "get_state with all passing health checks" do
      health_checkers = [
        fn -> :ok end,
        fn -> :ok end,
        fn -> :ok end
      ]

      result = SyncMonitor.get_state(health_checkers)
      assert result == [:ok, :ok, :ok]
    end

    test "get_state with mixed results" do
      health_checkers = [
        fn -> :ok end,
        fn -> {:halt, :unhealthy} end,
        fn -> :ok end
      ]

      result = SyncMonitor.get_state(health_checkers)
      assert result == [:ok, {:halt, :unhealthy}, :ok]
    end

    test "get_state with all failing checks" do
      health_checkers = [
        fn -> {:halt, :db_down} end,
        fn -> {:halt, :memory_high} end
      ]

      result = SyncMonitor.get_state(health_checkers)
      assert result == [{:halt, :db_down}, {:halt, :memory_high}]
    end

    test "get_state with single health check" do
      health_checkers = [fn -> :ok end]

      result = SyncMonitor.get_state(health_checkers)
      assert result == [:ok]
    end

    test "get_state executes all health checkers" do
      test_pid = self()

      health_checkers = [
        fn -> send(test_pid, :check1) && :ok end,
        fn -> send(test_pid, :check2) && :ok end,
        fn -> send(test_pid, :check3) && :ok end
      ]

      SyncMonitor.get_state(health_checkers)

      assert_receive :check1
      assert_receive :check2
      assert_receive :check3
    end

    test "get_state with empty health checkers list" do
      health_checkers = []
      result = SyncMonitor.get_state(health_checkers)
      assert result == []
    end
  end

  describe "AsyncMonitor" do
    test "starts and returns health check results" do
      health_checkers = [fn -> :ok end]
      {:ok, pid} = AsyncMonitor.start_link(health_checkers)

      # Give it time to run checks
      Process.sleep(100)

      result = AsyncMonitor.get_state(pid)
      assert result == [:ok]

      GenServer.stop(pid)
    end

    test "runs health checks in background" do
      test_pid = self()

      health_checkers = [
        fn ->
          send(test_pid, :health_check_executed)
          :ok
        end
      ]

      {:ok, pid} = AsyncMonitor.start_link(health_checkers)

      # Should execute checks in background
      assert_receive :health_check_executed, 1000

      GenServer.stop(pid)
    end

    test "updates state with new health check results" do
      health_checkers = [
        fn -> :ok end,
        fn -> {:halt, :warning} end
      ]

      {:ok, pid} = AsyncMonitor.start_link(health_checkers)
      Process.sleep(100)

      result = AsyncMonitor.get_state(pid)
      assert length(result) == 2
      assert :ok in result
      assert {:halt, :warning} in result

      GenServer.stop(pid)
    end
  end
end
