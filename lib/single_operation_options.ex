defmodule SingleOperationOptions do
  @moduledoc """
  Struct that holds single operation options, this is for the user to control and not batch.
  """

  alias Types

  @type health_check :: (() -> :ok | {:halt, any()})

  @type t :: %__MODULE__{
    handle: ((health_check()) -> {:ok, any()} | {:error, any()}),
    onComplete: ((any()) ->  any()),
    mode: Types.operation_mode(),
  }

  defstruct [:onComplete, :handle, :mode]
end
