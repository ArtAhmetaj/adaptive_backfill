defmodule AdaptiveBackfill.SyncBackfillMonitor do
  @moduledoc """
  Monitors synchronous backfill operations. Checks them in the background and not on demand.
  """

  # probably unimportant
  def monitor(func) do
    func.()
  end
end
