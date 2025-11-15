defmodule AdaptiveBackfill.MonitorResultEvaluator do
  @moduledoc """
  Evaluates based on rules whether we should stop or not.
  Currently simplistic.
  """

  def halt?(monitor_results) do
    Enum.any?(monitor_results, &match?({:halt, _}, &1))
  end
end
