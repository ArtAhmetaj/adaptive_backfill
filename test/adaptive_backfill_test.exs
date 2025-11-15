defmodule AdaptiveBackfillTest do
  use ExUnit.Case
  doctest AdaptiveBackfill

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
