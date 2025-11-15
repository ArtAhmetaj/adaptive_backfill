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
    * `:on_success` - Optional success callback
    * `:on_error` - Optional error callback
    * `:timeout` - Optional timeout in milliseconds
    * `:telemetry_prefix` - Optional telemetry event prefix (list of atoms)

  ## Example

      single_operation :my_operation do
        mode :sync
        health_checks [&check_health/0]
        timeout 30_000
        telemetry_prefix [:my_app, :operation]
        
        handle fn health_check -> :done end
        
        on_success fn result ->
          Logger.info("Operation succeeded")
        end
        
        on_error fn error ->
          Logger.error("Operation failed")
        end
      end
  """
  defmacro single_operation(name, do: block) do
    config = extract_dsl_config(block)

    quote do
      @backfills {:single, unquote(name)}

      def unquote(name)(opts \\ []) do
        handle = Keyword.get(opts, :handle, unquote(config[:handle]))
        on_complete = Keyword.get(opts, :on_complete, unquote(config[:on_complete]))
        on_success = Keyword.get(opts, :on_success, unquote(config[:on_success]))
        on_error = Keyword.get(opts, :on_error, unquote(config[:on_error]))
        mode = Keyword.get(opts, :mode, unquote(config[:mode] || :sync))
        health_checks = Keyword.get(opts, :health_checks, unquote(config[:health_checks]))
        timeout = Keyword.get(opts, :timeout, unquote(config[:timeout]))

        telemetry_prefix =
          Keyword.get(opts, :telemetry_prefix, unquote(config[:telemetry_prefix]))

        single_opts = [
          on_success: on_success,
          on_error: on_error,
          timeout: timeout,
          telemetry_prefix: telemetry_prefix
        ]

        case AdaptiveBackfill.SingleOperationOptions.new(handle, on_complete, mode, health_checks, single_opts) do
          {:ok, options} -> AdaptiveBackfill.SingleOperationProcessor.process(options)
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
    * `:on_success` - Optional success callback (called after each successful batch)
    * `:on_error` - Optional error callback (receives error and state)
    * `:delay_between_batches` - Milliseconds to wait between batches
    * `:timeout` - Milliseconds before timing out a batch
    * `:batch_size` - Number of items per batch (informational)
    * `:telemetry_prefix` - List of atoms for telemetry event prefix

  ## Example

      batch_operation :my_batch, initial_state: 0 do
        mode :async
        health_checks [&check_health/0]
        handle_batch fn state -> {:ok, state + 1} end
        delay_between_batches 1000
        timeout 30_000
        on_success fn state -> Logger.info("Batch succeeded") end
        on_error fn error, state -> Logger.error("Batch failed") end
        telemetry_prefix [:my_app, :backfill]
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
        on_success = Keyword.get(opts, :on_success, unquote(config[:on_success]))
        on_error = Keyword.get(opts, :on_error, unquote(config[:on_error]))
        mode = Keyword.get(opts, :mode, unquote(config[:mode] || :sync))
        health_checks = Keyword.get(opts, :health_checks, unquote(config[:health_checks]))
        initial_state = Keyword.get(opts, :initial_state, unquote(initial_state))

        delay_between_batches =
          Keyword.get(opts, :delay_between_batches, unquote(config[:delay_between_batches]))

        timeout = Keyword.get(opts, :timeout, unquote(config[:timeout]))
        batch_size = Keyword.get(opts, :batch_size, unquote(config[:batch_size]))

        telemetry_prefix =
          Keyword.get(opts, :telemetry_prefix, unquote(config[:telemetry_prefix]))

        batch_opts = [
          on_success: on_success,
          on_error: on_error,
          delay_between_batches: delay_between_batches,
          timeout: timeout,
          batch_size: batch_size,
          telemetry_prefix: telemetry_prefix
        ]

        case AdaptiveBackfill.BatchOperationOptions.new(
               initial_state,
               handle_batch,
               on_complete,
               mode,
               health_checks,
               batch_opts
             ) do
          {:ok, options} -> AdaptiveBackfill.BatchOperationProcessor.process(options)
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
        {:on_success, _, [value]} -> Map.put(acc, :on_success, value)
        {:on_error, _, [value]} -> Map.put(acc, :on_error, value)
        {:delay_between_batches, _, [value]} -> Map.put(acc, :delay_between_batches, value)
        {:timeout, _, [value]} -> Map.put(acc, :timeout, value)
        {:batch_size, _, [value]} -> Map.put(acc, :batch_size, value)
        {:telemetry_prefix, _, [value]} -> Map.put(acc, :telemetry_prefix, value)
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
      {:on_success, _, [value]} -> %{on_success: value}
      {:on_error, _, [value]} -> %{on_error: value}
      {:delay_between_batches, _, [value]} -> %{delay_between_batches: value}
      {:timeout, _, [value]} -> %{timeout: value}
      {:batch_size, _, [value]} -> %{batch_size: value}
      {:telemetry_prefix, _, [value]} -> %{telemetry_prefix: value}
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

  @doc """
  Sets the on_success callback (called after each successful batch).
  """
  defmacro on_success(func) do
    quote do: {:on_success, unquote(func)}
  end

  @doc """
  Sets the on_error callback (receives error and state).
  """
  defmacro on_error(func) do
    quote do: {:on_error, unquote(func)}
  end

  @doc """
  Sets the delay between batches in milliseconds.
  """
  defmacro delay_between_batches(ms) do
    quote do: {:delay_between_batches, unquote(ms)}
  end

  @doc """
  Sets the timeout for each batch in milliseconds.
  """
  defmacro timeout(ms) do
    quote do: {:timeout, unquote(ms)}
  end

  @doc """
  Sets the batch size (informational, for user's handle_batch logic).
  """
  defmacro batch_size(size) do
    quote do: {:batch_size, unquote(size)}
  end

  @doc """
  Sets the telemetry event prefix (list of atoms).
  """
  defmacro telemetry_prefix(prefix) do
    quote do: {:telemetry_prefix, unquote(prefix)}
  end

  # Non-DSL API
  @doc """
  Run a backfill with options struct (non-DSL API).
  """
  @spec run(AdaptiveBackfill.SingleOperationOptions.t() | AdaptiveBackfill.BatchOperationOptions.t()) :: :ok | :halt | :done
  def run(opts) do
    case opts do
      %AdaptiveBackfill.SingleOperationOptions{} -> AdaptiveBackfill.SingleOperationProcessor.process(opts)
      %AdaptiveBackfill.BatchOperationOptions{} -> AdaptiveBackfill.BatchOperationProcessor.process(opts)
    end
  end
end
