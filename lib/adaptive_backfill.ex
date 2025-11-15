defmodule AdaptiveBackfill do
  @moduledoc """
  DSL for creating adaptive backfills with health checks.

  ## Usage

      defmodule MyBackfill do
        use AdaptiveBackfill

        single_operation :process_user do
          mode :sync
          health_checks [&check_db/0, &check_memory/0]
          
          handle fn health_check ->
            case health_check.() do
              :ok -> :done
              {:halt, reason} -> {:halt, reason}
            end
          end
        end

        batch_operation :process_batch, initial_state: 0 do
          mode :async
          health_checks [&check_db/0]
          
          handle_batch fn state ->
            if state < 100, do: {:ok, state + 1}, else: :done
          end
        end
      end

      # Run the backfills
      MyBackfill.process_user()
      MyBackfill.process_batch()
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import AdaptiveBackfill
      Module.register_attribute(__MODULE__, :backfills, accumulate: true)
      @before_compile AdaptiveBackfill
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      def __backfills__, do: @backfills
    end
  end

  @doc """
  Defines a single operation backfill.

  ## Options

    * `:mode` - Either `:sync` or `:async` (default: `:sync`)
    * `:health_checks` - List of health check functions
    * `:handle` - The operation handler function
    * `:on_complete` - Optional completion callback

  ## Example

      single_operation :my_operation do
        mode :sync
        health_checks [&check_health/0]
        handle fn health_check -> :done end
      end
  """
  defmacro single_operation(name, do: block) do
    config = extract_dsl_config(block)
    
    quote do
      @backfills {:single, unquote(name)}
      
      def unquote(name)(opts \\ []) do
        handle = Keyword.get(opts, :handle, unquote(config[:handle]))
        on_complete = Keyword.get(opts, :on_complete, unquote(config[:on_complete]))
        mode = Keyword.get(opts, :mode, unquote(config[:mode] || :sync))
        health_checks = Keyword.get(opts, :health_checks, unquote(config[:health_checks]))
        
        case SingleOperationOptions.new(handle, on_complete, mode, health_checks) do
          {:ok, options} -> SingleOperationProcessor.process(options)
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  @doc """
  Defines a batch operation backfill.

  ## Options

    * `:initial_state` - The starting state for the batch processor
    * `:mode` - Either `:sync` or `:async` (default: `:sync`)
    * `:health_checks` - List of health check functions
    * `:handle_batch` - The batch handler function
    * `:on_complete` - Optional completion callback

  ## Example

      batch_operation :my_batch, initial_state: 0 do
        mode :async
        health_checks [&check_health/0]
        handle_batch fn state -> {:ok, state + 1} end
      end
  """
  defmacro batch_operation(name, opts \\ [], do: block) do
    initial_state = Keyword.get(opts, :initial_state)
    config = extract_dsl_config(block)
    
    quote do
      @backfills {:batch, unquote(name)}
      
      def unquote(name)(opts \\ []) do
        handle_batch = Keyword.get(opts, :handle_batch, unquote(config[:handle_batch]))
        on_complete = Keyword.get(opts, :on_complete, unquote(config[:on_complete]))
        mode = Keyword.get(opts, :mode, unquote(config[:mode] || :sync))
        health_checks = Keyword.get(opts, :health_checks, unquote(config[:health_checks]))
        initial_state = Keyword.get(opts, :initial_state, unquote(initial_state))
        
        case BatchOperationOptions.new(initial_state, handle_batch, on_complete, mode, health_checks) do
          {:ok, options} -> BatchOperationProcessor.process(options)
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  @doc false
  def extract_dsl_config({:__block__, _, expressions}) do
    Enum.reduce(expressions, %{}, fn expr, acc ->
      case expr do
        {:mode, _, [value]} -> Map.put(acc, :mode, value)
        {:health_checks, _, [value]} -> Map.put(acc, :health_checks, value)
        {:handle, _, [value]} -> Map.put(acc, :handle, value)
        {:handle_batch, _, [value]} -> Map.put(acc, :handle_batch, value)
        {:on_complete, _, [value]} -> Map.put(acc, :on_complete, value)
        _ -> acc
      end
    end)
  end
  
  def extract_dsl_config(single_expr) do
    case single_expr do
      {:mode, _, [value]} -> %{mode: value}
      {:health_checks, _, [value]} -> %{health_checks: value}
      {:handle, _, [value]} -> %{handle: value}
      {:handle_batch, _, [value]} -> %{handle_batch: value}
      {:on_complete, _, [value]} -> %{on_complete: value}
      _ -> %{}
    end
  end

  @doc """
  Sets the operation mode.
  """
  defmacro mode(value) do
    quote do: {:mode, unquote(value)}
  end

  @doc """
  Sets the health checks.
  """
  defmacro health_checks(checks) do
    quote do: {:health_checks, unquote(checks)}
  end

  @doc """
  Sets the handle function for single operations.
  """
  defmacro handle(func) do
    quote do: {:handle, unquote(func)}
  end

  @doc """
  Sets the handle_batch function for batch operations.
  """
  defmacro handle_batch(func) do
    quote do: {:handle_batch, unquote(func)}
  end

  @doc """
  Sets the on_complete callback.
  """
  defmacro on_complete(func) do
    quote do: {:on_complete, unquote(func)}
  end

  # Legacy API for backwards compatibility
  @doc """
  Run a backfill with options struct (legacy API).
  """
  @spec run(%SingleOperationOptions{} | %BatchOperationOptions{}) :: :ok | :halt | :done
  def run(opts) do
    case opts do
      %SingleOperationOptions{} -> SingleOperationProcessor.process(opts)
      %BatchOperationOptions{} -> BatchOperationProcessor.process(opts)
    end
  end
end
