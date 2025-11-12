defmodule MonitorOperation do

  @type monitor_operation_fetch :: (() -> any())

  @type monitor_importance :: :low | :medium | :high

  @type t :: %__MODULE__{
    operation_func: monitor_operation_fetch(),
    importance: monitor_importance()
  }
  defstruct [:operation_func, :importance]
end
