defmodule BatchOperationProcessor do
  alias BatchOperationOptions

  #  initial_state: any(),
  #         handle_batch: ((any()) -> (any())),
  #         on_complete: ((any()) ->  any()),
  #         mode: Types.operation_mode(),
  #         health_checkers: [Types.health_checker()]

  def process(%BatchOperationOptions{
        initial_state: initial_state,
        handle_batch: handle_batch,
        on_complete: on_complete,
        mode: mode,
        health_checkers: health_checkers
      }) do


        
      end
end
