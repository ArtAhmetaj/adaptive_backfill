defmodule ContinuationEvalutor do

  @spec evaluate([{MonitorOperation.monitor_importance(), boolean()}])
  def evaluate([]) do

    {:error, :invalid_monitor_state} #should always have an importance set
  end


  def evaluate(importance_results) do
    
  end
end
