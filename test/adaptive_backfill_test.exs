defmodule AdaptiveBackfillTest do
  use ExUnit.Case
  doctest AdaptiveBackfill

  defmodule ExampleBackfill do
    use AdaptiveBackfill

    single_operation :process_item do
      mode :sync
      health_checks [fn -> :ok end]
      handle fn _health_check -> :done end
    end

    batch_operation :process_items, initial_state: 0 do
      mode :sync
      health_checks [fn -> :ok end]

      handle_batch fn
        0 -> {:ok, 1}
        1 -> :done
      end
    end
  end

  describe "DSL API" do
    test "single_operation creates a callable function" do
      assert {:ok, :done} = ExampleBackfill.process_item()
    end

    test "batch_operation creates a callable function" do
      assert {:ok, :done} = ExampleBackfill.process_items()
    end
  end

  describe "Non DSL API" do
    test "run/1 accepts SingleOperationOptions" do
      handle = fn _health_check -> :done end
      {:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, [fn -> :ok end])
      result = AdaptiveBackfill.run(opts)
      assert result == {:ok, :done}
    end

    test "run/1 accepts BatchOperationOptions" do
      handle_batch = fn
        0 -> {:ok, 1}
        1 -> :done
      end
      {:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :sync, [fn -> :ok end])
      result = AdaptiveBackfill.run(opts)
      assert result == {:ok, :done}
    end
  end
end
