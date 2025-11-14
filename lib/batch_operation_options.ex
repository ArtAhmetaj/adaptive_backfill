defmodule BatchOperationOptions do
  @moduledoc """
  Struct that holds config for batch operations, used for pagination or chunked behaviour.
  """

  alias Types

  @type t :: %__MODULE__{
          initial_state: any(),
          handle_batch: ((any()) -> (any())),
          on_complete: ((any()) ->  any()),
          mode: Types.operation_mode(),

        }

  defstruct [:initial_state, :handle_batch, :on_complete, :mode]
end
