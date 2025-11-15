defmodule SingleOperationFeaturesTest do
  use ExUnit.Case

  defmodule TestSingleOps do
    use AdaptiveBackfill

    single_operation :simple do
      mode :sync
      health_checks [fn -> :ok end]
      handle fn _health_check -> :done end
    end

    single_operation :with_timeout do
      mode :sync
      health_checks [fn -> :ok end]
      timeout 5000
      handle fn _health_check -> {:ok, :result} end
    end

    single_operation :with_success do
      mode :sync
      health_checks [fn -> :ok end]
      handle fn _health_check -> {:ok, :success} end
      on_success fn result -> send(self(), {:success, result}) end
    end

    single_operation :with_error_handler do
      mode :sync
      health_checks [fn -> :ok end]
      handle fn _health_check -> {:error, :test_error} end
      on_error fn error -> send(self(), {:error, error}) end
    end

    single_operation :with_telemetry do
      mode :sync
      health_checks [fn -> :ok end]
      telemetry_prefix [:test, :single]
      handle fn _health_check -> :done end
    end

    single_operation :with_all_features do
      mode :async
      health_checks [fn -> :ok end]
      timeout 10_000
      telemetry_prefix [:test, :all_features]
      
      handle fn _health_check -> {:ok, :completed} end
      
      on_success fn result ->
        send(self(), {:on_success, result})
      end
      
      on_error fn error ->
        send(self(), {:on_error, error})
      end
      
      on_complete fn result ->
        send(self(), {:on_complete, result})
      end
    end

    single_operation :with_health_check_halt do
      mode :sync
      health_checks [fn -> {:halt, :unhealthy} end]
      handle fn health_check ->
        case health_check.() do
          :ok -> :done
          {:halt, reason} -> {:halt, reason}
        end
      end
    end
  end

  describe "single_operation DSL" do
    test "simple operation works" do
      assert {:ok, :done} = TestSingleOps.simple()
    end

    test "operation with timeout" do
      assert {:ok, :result} = TestSingleOps.with_timeout()
    end

    test "operation with success callback" do
      assert {:ok, :success} = TestSingleOps.with_success()
      assert_receive {:success, :success}
    end

    test "operation with error handler" do
      assert {:error, :test_error} = TestSingleOps.with_error_handler()
      assert_receive {:error, :test_error}
    end

    test "operation with telemetry" do
      events = capture_telemetry_events([:test, :single], fn ->
        TestSingleOps.with_telemetry()
      end)

      event_names = Enum.map(events, fn {name, _, _} -> name end)
      assert [:test, :single, :start] in event_names
      assert [:test, :single, :success] in event_names
    end

    test "operation with all features" do
      events = capture_telemetry_events([:test, :all_features], fn ->
        assert {:ok, :completed} = TestSingleOps.with_all_features()
      end)

      assert_receive {:on_success, :completed}
      assert_receive {:on_complete, :completed}
      
      assert length(events) > 0
    end

    test "operation with health check halt" do
      result = TestSingleOps.with_health_check_halt()
      assert match?({:halt, _}, result)
    end

    test "can override options at runtime" do
      custom_handle = fn _health_check -> {:ok, :custom} end
      assert {:ok, :custom} = TestSingleOps.simple(handle: custom_handle)
    end

    test "can override timeout at runtime" do
      assert {:ok, :result} = TestSingleOps.with_timeout(timeout: 1000)
    end

    test "can override telemetry_prefix at runtime" do
      events = capture_telemetry_events([:custom, :prefix], fn ->
        TestSingleOps.simple(telemetry_prefix: [:custom, :prefix])
      end)

      event_names = Enum.map(events, fn {name, _, _} -> name end)
      assert [:custom, :prefix, :start] in event_names
    end
  end

  describe "single operation error handling" do
    defmodule ErrorOps do
      use AdaptiveBackfill

      single_operation :raises_error do
        mode :sync
        health_checks [fn -> :ok end]
        handle fn _health_check -> raise "Intentional error" end
        on_error fn error -> send(self(), {:caught, error}) end
      end

      single_operation :exits do
        mode :sync
        health_checks [fn -> :ok end]
        handle fn _health_check -> exit(:normal) end
        on_error fn error -> send(self(), {:caught_exit, error}) end
      end
    end

    test "catches exceptions" do
      assert {:error, %RuntimeError{}} = ErrorOps.raises_error()
      assert_receive {:caught, %RuntimeError{message: "Intentional error"}}
    end

    test "catches exits" do
      assert {:error, {:exit, :normal}} = ErrorOps.exits()
      assert_receive {:caught_exit, {:exit, :normal}}
    end
  end

  describe "single operation with async mode" do
    defmodule AsyncOps do
      use AdaptiveBackfill

      single_operation :async_operation do
        mode :async
        health_checks [fn -> :ok end]
        handle fn _health_check -> {:ok, :async_result} end
      end
    end

    test "async mode works" do
      assert {:ok, :async_result} = AsyncOps.async_operation()
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
        prefix ++ [:success],
        prefix ++ [:halt],
        prefix ++ [:error],
        prefix ++ [:exception],
        prefix ++ [:exit]
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
