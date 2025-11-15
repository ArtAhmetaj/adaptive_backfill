defmodule AdaptiveBackfill.Types do
  @moduledoc """
  Common type definitions.
  """
  @type operation_mode :: :sync | :async

  @type health_check_result :: :ok | {:halt, any()}

  @type health_checker :: (any() -> health_check_result())
end
