defmodule SyncBackfillMonitor do

  #probably unimportant 
  def monitor(func) do
    func.()
  end

end
