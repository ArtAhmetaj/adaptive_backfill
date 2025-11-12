defmodule MonitorInitState do

  @type fetcher_func :: (() -> any())


  @type t :: %__MODULE__{
    init_state: any(),

  }


  defstruct [:init_state, :fetcher_funcs]
end
