defmodule SyncMonitorTest do
  use ExUnit.Case

  describe "get_state/1" do
    test "returns :ok for all healthy checkers" do
      health_checkers = [
        fn -> :ok end,
        fn -> :ok end,
        fn -> :ok end
      ]

      results = SyncMonitor.get_state(health_checkers)
      assert results == [:ok, :ok, :ok]
    end

    test "returns mixed results when some checkers return different values" do
      health_checkers = [
        fn -> :ok end,
        fn -> {:halt, :timeout} end,
        fn -> :ok end
      ]

      results = SyncMonitor.get_state(health_checkers)
      assert results == [:ok, {:halt, :timeout}, :ok]
    end

    test "handles single health checker" do
      health_checkers = [
        fn -> :ok end
      ]

      results = SyncMonitor.get_state(health_checkers)
      assert results == [:ok]
    end

    test "returns different status values" do
      health_checkers = [
        fn -> :ok end,
        fn -> {:halt, :cpu_high} end,
        fn -> {:halt, :memory_high} end
      ]

      results = SyncMonitor.get_state(health_checkers)
      assert results == [:ok, {:halt, :cpu_high}, {:halt, :memory_high}]
    end
  end
end
