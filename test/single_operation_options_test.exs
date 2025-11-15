defmodule SingleOperationOptionsTest do
  use ExUnit.Case

  describe "new/4" do
    test "creates valid single operation options with all required fields" do
      handle = fn _health_check -> {:ok, :result} end
      on_complete = fn _state -> :ok end
      health_checkers = [fn -> :ok end, fn -> :ok end]

      assert {:ok, opts} = SingleOperationOptions.new(handle, on_complete, :sync, health_checkers)
      assert is_function(opts.handle, 1)
      assert is_function(opts.on_complete, 1)
      assert opts.mode == :sync
      assert length(opts.health_checkers) == 2
    end

    test "creates valid single operation options with async mode" do
      handle = fn _health_check -> {:ok, :result} end
      on_complete = fn _state -> :ok end
      health_checkers = [fn -> :ok end]

      assert {:ok, opts} = SingleOperationOptions.new(handle, on_complete, :async, health_checkers)
      assert opts.mode == :async
    end

    test "accepts nil on_complete" do
      handle = fn _health_check -> {:ok, :result} end
      health_checkers = [fn -> :ok end]

      assert {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
      assert opts.on_complete == nil
    end

    test "returns error when handle is nil" do
      health_checkers = [fn -> :ok end]
      assert {:error, :invalid_handle} = SingleOperationOptions.new(nil, nil, :sync, health_checkers)
    end

    test "returns error when handle is not a function" do
      health_checkers = [fn -> :ok end]
      assert {:error, :invalid_handle} = SingleOperationOptions.new("not a function", nil, :sync, health_checkers)
    end

    test "returns error when handle has wrong arity" do
      handle = fn -> :ok end
      health_checkers = [fn -> :ok end]
      assert {:error, :invalid_handle} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
    end

    test "returns error when on_complete has wrong arity" do
      handle = fn _health_check -> {:ok, :result} end
      on_complete = fn -> :ok end
      health_checkers = [fn -> :ok end]
      assert {:error, :invalid_on_complete} = SingleOperationOptions.new(handle, on_complete, :sync, health_checkers)
    end

    test "returns error when mode is invalid" do
      handle = fn _health_check -> {:ok, :result} end
      health_checkers = [fn -> :ok end]
      assert {:error, :invalid_mode} = SingleOperationOptions.new(handle, nil, :invalid, health_checkers)
    end

    test "returns error when health_checkers is nil" do
      handle = fn _health_check -> {:ok, :result} end
      assert {:error, :invalid_health_checkers} = SingleOperationOptions.new(handle, nil, :sync, nil)
    end

    test "returns error when health_checkers is empty list" do
      handle = fn _health_check -> {:ok, :result} end
      assert {:error, :invalid_health_checkers} = SingleOperationOptions.new(handle, nil, :sync, [])
    end

    test "returns error when health_checkers contains non-functions" do
      handle = fn _health_check -> {:ok, :result} end
      health_checkers = [fn -> :ok end, "not a function"]
      assert {:error, :invalid_health_checkers} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
    end

    test "returns error when health_checkers contains functions with wrong arity" do
      handle = fn _health_check -> {:ok, :result} end
      health_checkers = [fn -> :ok end, fn x -> x end]
      assert {:error, :invalid_health_checkers} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
    end
  end
end
