defmodule BatchOperationOptionsTest do
  use ExUnit.Case

  describe "new/5" do
    test "creates valid batch operation options with all required fields" do
      handle_batch = fn state -> {:ok, state + 1} end
      on_complete = fn _state -> :ok end
      health_checkers = [fn -> :ok end, fn -> :ok end]

      assert {:ok, opts} = BatchOperationOptions.new(0, handle_batch, on_complete, :sync, health_checkers)
      assert opts.initial_state == 0
      assert is_function(opts.handle_batch, 1)
      assert is_function(opts.on_complete, 1)
      assert opts.mode == :sync
      assert length(opts.health_checkers) == 2
    end

    test "creates valid batch operation options with async mode" do
      handle_batch = fn state -> {:ok, state + 1} end
      on_complete = fn _state -> :ok end
      health_checkers = [fn -> :ok end]

      assert {:ok, opts} = BatchOperationOptions.new(0, handle_batch, on_complete, :async, health_checkers)
      assert opts.mode == :async
    end

    test "accepts nil on_complete" do
      handle_batch = fn state -> {:ok, state + 1} end
      health_checkers = [fn -> :ok end]

      assert {:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers)
      assert opts.on_complete == nil
    end

    test "returns error when handle_batch is nil" do
      health_checkers = [fn -> :ok end]
      assert {:error, :invalid_handle_batch} = BatchOperationOptions.new(0, nil, nil, :sync, health_checkers)
    end

    test "returns error when handle_batch is not a function" do
      health_checkers = [fn -> :ok end]
      assert {:error, :invalid_handle_batch} = BatchOperationOptions.new(0, "not a function", nil, :sync, health_checkers)
    end

    test "returns error when handle_batch has wrong arity" do
      handle_batch = fn -> :ok end
      health_checkers = [fn -> :ok end]
      assert {:error, :invalid_handle_batch} = BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers)
    end

    test "returns error when on_complete has wrong arity" do
      handle_batch = fn state -> {:ok, state} end
      on_complete = fn -> :ok end
      health_checkers = [fn -> :ok end]
      assert {:error, :invalid_on_complete} = BatchOperationOptions.new(0, handle_batch, on_complete, :sync, health_checkers)
    end

    test "returns error when mode is invalid" do
      handle_batch = fn state -> {:ok, state} end
      health_checkers = [fn -> :ok end]
      assert {:error, :invalid_mode} = BatchOperationOptions.new(0, handle_batch, nil, :invalid, health_checkers)
    end

    test "returns error when health_checkers is nil" do
      handle_batch = fn state -> {:ok, state} end
      assert {:error, :invalid_health_checkers} = BatchOperationOptions.new(0, handle_batch, nil, :sync, nil)
    end

    test "returns error when health_checkers is empty list" do
      handle_batch = fn state -> {:ok, state} end
      assert {:error, :invalid_health_checkers} = BatchOperationOptions.new(0, handle_batch, nil, :sync, [])
    end

    test "returns error when health_checkers contains non-functions" do
      handle_batch = fn state -> {:ok, state} end
      health_checkers = [fn -> :ok end, "not a function"]
      assert {:error, :invalid_health_checkers} = BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers)
    end

    test "returns error when health_checkers contains functions with wrong arity" do
      handle_batch = fn state -> {:ok, state} end
      health_checkers = [fn -> :ok end, fn x -> x end]
      assert {:error, :invalid_health_checkers} = BatchOperationOptions.new(0, handle_batch, nil, :sync, health_checkers)
    end
  end
end
