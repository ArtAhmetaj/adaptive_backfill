defmodule AdaptiveBackfill do
  @moduledoc """
  Entry point for creating an adaptive backfill.
  Can create a single operation backfill or a batch one.
  """

  @spec run(%SingleOperationOptions{} | %BatchOperationOptions{}) :: :ok | :halt | :done
  def run(opts) do
    case opts do
      %SingleOperationOptions{} -> SingleOperationProcessor.process(opts)
      %BatchOperationOptions{} -> BatchOperationProcessor.process(opts)
    end
  end
end
