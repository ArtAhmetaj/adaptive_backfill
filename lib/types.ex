defmodule Types do
  @type operation_mode :: :sync | :async

  @type health_checker :: ((any()) -> :ok | {:halt, any()})
end
