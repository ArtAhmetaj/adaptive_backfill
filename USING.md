# Using AdaptiveBackfill DSL

This guide explains how to use the AdaptiveBackfill DSL to create adaptive backfill operations.

## Table of Contents

- [Quick Start](#quick-start)
- [Single Operations](#single-operations)
- [Batch Operations](#batch-operations)
- [Health Checks](#health-checks)
- [Callbacks](#callbacks)
- [Telemetry](#telemetry)
- [Advanced Features](#advanced-features)
- [Best Practices](#best-practices)

## Quick Start

```elixir
defmodule MyApp.Backfills do
  use AdaptiveBackfill

  # Define a simple batch operation
  batch_operation :migrate_users, initial_state: 0 do
    mode :async
    health_checks [&check_database/0]
    
    handle_batch fn offset ->
      users = fetch_users(offset, 100)
      if Enum.empty?(users) do
        :done
      else
        migrate_users(users)
        {:ok, offset + 100}
      end
    end
  end
  
  defp check_database, do: :ok
end

# Run it
MyApp.Backfills.migrate_users()
```

## Single Operations

Single operations give you full control over when health checks are performed. You receive a `health_check` callback that you can call at any point in your operation.

### Basic Single Operation

```elixir
single_operation :process_user do
  mode :sync
  health_checks [&check_database/0, &check_memory/0]
  
  handle fn health_check ->
    # Do some work
    user = get_user()
    
    # Check health before continuing
    case health_check.() do
      :ok -> 
        process_user(user)
        :done
      {:halt, reason} -> 
        {:halt, reason}
    end
  end
end
```

### Single Operation with All Features

```elixir
single_operation :complex_operation do
  mode :async
  health_checks [&check_database/0, &check_api_rate_limit/0]
  timeout 30_000
  telemetry_prefix [:my_app, :backfill, :complex]
  
  handle fn health_check ->
    # Step 1: Fetch data
    data = fetch_data()
    
    # Check health before expensive operation
    case health_check.() do
      :ok -> 
        # Step 2: Process data
        result = process_data(data)
        
        # Check health again
        case health_check.() do
          :ok -> {:ok, result}
          {:halt, reason} -> {:halt, reason}
        end
      {:halt, reason} -> 
        {:halt, reason}
    end
  end
  
  on_success fn result ->
    Logger.info("Operation succeeded: #{inspect(result)}")
    Metrics.increment("backfill.success")
  end
  
  on_error fn error ->
    Logger.error("Operation failed: #{inspect(error)}")
    Sentry.capture_exception(error)
  end
  
  on_complete fn result ->
    Logger.info("Operation completed: #{inspect(result)}")
  end
end
```

### Single Operation Return Values

```elixir
# Success - operation completed
handle fn _hc -> :done end
handle fn _hc -> {:ok, result} end

# Halt - health check failed
handle fn _hc -> {:halt, reason} end

# Error - operation failed
handle fn _hc -> {:error, reason} end
```

## Batch Operations

Batch operations automatically run health checks between batches. You focus on processing each batch, and the library handles health monitoring.

### Basic Batch Operation

```elixir
batch_operation :migrate_posts, initial_state: 0 do
  mode :sync
  health_checks [&check_database/0]
  
  handle_batch fn offset ->
    posts = Repo.all(from p in Post, offset: ^offset, limit: 100)
    
    if Enum.empty?(posts) do
      :done
    else
      Enum.each(posts, &migrate_post/1)
      {:ok, offset + 100}
    end
  end
end
```

### Batch Operation with All Features

```elixir
batch_operation :sync_external_data, initial_state: %{page: 1, total: 0} do
  mode :async
  health_checks [
    &check_database/0,
    &check_api_rate_limit/0,
    &check_memory_usage/0
  ]
  delay_between_batches 1000  # Wait 1 second between batches
  timeout 60_000              # 60 second timeout per batch
  batch_size 50               # Process 50 items per batch
  telemetry_prefix [:my_app, :sync]
  
  handle_batch fn state ->
    case fetch_from_api(state.page, 50) do
      {:ok, [], _meta} ->
        Logger.info("Synced #{state.total} total items")
        :done
        
      {:ok, items, meta} ->
        sync_items(items)
        {:ok, %{page: state.page + 1, total: state.total + length(items)}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  on_success fn state ->
    Logger.info("Batch #{state.page} completed, total: #{state.total}")
    Metrics.increment("sync.batch.success")
  end
  
  on_error fn error, state ->
    Logger.error("Batch #{state.page} failed: #{inspect(error)}")
    Sentry.capture_exception(error, extra: %{state: state})
  end
  
  on_complete fn result ->
    Logger.info("Sync completed: #{inspect(result)}")
    send_notification("Sync finished")
  end
end
```

### Batch Operation Return Values

```elixir
# Continue - process next batch
handle_batch fn state -> {:ok, next_state} end

# Done - all batches processed
handle_batch fn _state -> :done end

# Error - batch failed (stops processing)
handle_batch fn _state -> {:error, reason} end
```

## Health Checks

Health checks are functions that return `:ok` or `{:halt, reason}`.

### Simple Health Checks

```elixir
defmodule MyApp.HealthChecks do
  def check_database do
    case Repo.query("SELECT 1") do
      {:ok, _} -> :ok
      {:error, _} -> {:halt, :database_down}
    end
  end
  
  def check_memory do
    memory = :erlang.memory(:total)
    max_memory = 1_000_000_000  # 1GB
    
    if memory < max_memory do
      :ok
    else
      {:halt, :memory_high}
    end
  end
  
  def check_api_rate_limit do
    case RateLimiter.check() do
      :ok -> :ok
      :rate_limited -> {:halt, :rate_limit_exceeded}
    end
  end
end
```

### PostgreSQL Health Checks

The library includes built-in PostgreSQL health checkers:

```elixir
batch_operation :migrate, initial_state: 0 do
  mode :async
  
  # Use all default PostgreSQL health checks
  health_checks DefaultPgHealthCheckers.pg_health_checks(MyApp.Repo)
  
  handle_batch fn state -> {:ok, state + 1} end
end

# Or use individual checks
batch_operation :migrate, initial_state: 0 do
  mode :async
  
  health_checks [
    &DefaultPgHealthCheckers.long_waiting_queries(MyApp.Repo)/0,
    &DefaultPgHealthCheckers.hot_io_tables(MyApp.Repo)/0,
    &DefaultPgHealthCheckers.temp_file_usage(MyApp.Repo)/0
  ]
  
  handle_batch fn state -> {:ok, state + 1} end
end
```

## Callbacks

### on_success

Called after each successful operation (single) or batch (batch operations).

```elixir
# Single operation
single_operation :process do
  health_checks [&check/0]
  handle fn _hc -> {:ok, :result} end
  
  on_success fn result ->
    Logger.info("Success: #{inspect(result)}")
  end
end

# Batch operation - called after EACH successful batch
batch_operation :migrate, initial_state: 0 do
  health_checks [&check/0]
  handle_batch fn state -> {:ok, state + 1} end
  
  on_success fn next_state ->
    Logger.info("Batch completed, next state: #{next_state}")
  end
end
```

### on_error

Called when an operation fails or raises an exception.

```elixir
# Single operation - receives error
single_operation :process do
  health_checks [&check/0]
  handle fn _hc -> {:error, :failed} end
  
  on_error fn error ->
    Logger.error("Failed: #{inspect(error)}")
    Sentry.capture_exception(error)
  end
end

# Batch operation - receives error AND state
batch_operation :migrate, initial_state: 0 do
  health_checks [&check/0]
  handle_batch fn state -> {:error, :failed} end
  
  on_error fn error, state ->
    Logger.error("Batch failed at state #{state}: #{inspect(error)}")
    Sentry.capture_exception(error, extra: %{state: state})
  end
end
```

### on_complete

Called once at the end of the entire operation.

```elixir
single_operation :process do
  health_checks [&check/0]
  handle fn _hc -> :done end
  
  on_complete fn result ->
    Logger.info("Operation finished: #{inspect(result)}")
    send_notification("Backfill complete")
  end
end
```

## Telemetry

Enable telemetry to monitor your backfills in production.

### Enabling Telemetry

```elixir
batch_operation :migrate, initial_state: 0 do
  mode :async
  health_checks [&check/0]
  telemetry_prefix [:my_app, :backfill, :migrate]
  
  handle_batch fn state -> {:ok, state + 1} end
end
```

### Telemetry Events

**Single Operations:**
- `[:my_app, :backfill, :migrate, :start]` - Operation started
- `[:my_app, :backfill, :migrate, :success]` - Operation succeeded
- `[:my_app, :backfill, :migrate, :error]` - Operation failed
- `[:my_app, :backfill, :migrate, :halt]` - Health check halted operation
- `[:my_app, :backfill, :migrate, :exception]` - Exception raised
- `[:my_app, :backfill, :migrate, :exit]` - Process exited

**Batch Operations:**
- `[:my_app, :backfill, :migrate, :start]` - Backfill started
- `[:my_app, :backfill, :migrate, :stop]` - Backfill finished
- `[:my_app, :backfill, :migrate, :batch, :start]` - Batch started
- `[:my_app, :backfill, :migrate, :batch, :success]` - Batch succeeded
- `[:my_app, :backfill, :migrate, :batch, :done]` - Final batch
- `[:my_app, :backfill, :migrate, :batch, :error]` - Batch failed
- `[:my_app, :backfill, :migrate, :health_check, :halt]` - Health check failed

### Attaching Telemetry Handlers

```elixir
:telemetry.attach(
  "my-backfill-handler",
  [:my_app, :backfill, :migrate, :batch, :success],
  fn _event, measurements, metadata, _config ->
    Logger.info("Batch completed in #{measurements.duration}ns")
    Metrics.timing("backfill.batch.duration", measurements.duration)
  end,
  nil
)
```

### Integration with Telemetry.Metrics

```elixir
defmodule MyApp.Telemetry do
  import Telemetry.Metrics

  def metrics do
    [
      # Count successful batches
      counter("backfill.batch.success.count",
        event_name: [:my_app, :backfill, :migrate, :batch, :success]
      ),
      
      # Track batch duration
      distribution("backfill.batch.duration",
        event_name: [:my_app, :backfill, :migrate, :batch, :success],
        measurement: :duration,
        unit: {:native, :millisecond}
      ),
      
      # Count errors
      counter("backfill.batch.error.count",
        event_name: [:my_app, :backfill, :migrate, :batch, :error]
      )
    ]
  end
end
```

## Advanced Features

### Timeout

Prevent operations from hanging:

```elixir
single_operation :slow_operation do
  health_checks [&check/0]
  timeout 30_000  # 30 seconds
  
  handle fn _hc ->
    # If this takes longer than 30s, it will timeout
    slow_operation()
    :done
  end
end

batch_operation :slow_batch, initial_state: 0 do
  health_checks [&check/0]
  timeout 60_000  # 60 seconds per batch
  
  handle_batch fn state ->
    # Each batch has 60 seconds to complete
    slow_batch_operation()
    {:ok, state + 1}
  end
end
```

### Delay Between Batches

Add breathing room between batches:

```elixir
batch_operation :rate_limited_sync, initial_state: 0 do
  health_checks [&check/0]
  delay_between_batches 2000  # Wait 2 seconds between batches
  
  handle_batch fn state ->
    call_external_api()
    {:ok, state + 1}
  end
end
```

### Batch Size (Informational)

Document your batch size for clarity:

```elixir
batch_operation :migrate, initial_state: 0 do
  health_checks [&check/0]
  batch_size 100  # Process 100 items per batch
  
  handle_batch fn offset ->
    items = fetch_items(offset, 100)  # Use batch_size here
    process_items(items)
    {:ok, offset + 100}
  end
end
```

### Runtime Overrides

Override any option at runtime:

```elixir
# Override timeout
MyApp.Backfills.migrate_users(timeout: 120_000)

# Override initial state
MyApp.Backfills.migrate_users(initial_state: 1000)

# Override health checks
MyApp.Backfills.migrate_users(health_checks: [&my_custom_check/0])

# Override multiple options
MyApp.Backfills.migrate_users(
  initial_state: 500,
  timeout: 60_000,
  delay_between_batches: 500,
  mode: :sync
)
```

### Sync vs Async Mode

**Sync Mode:**
- Health checks run on-demand when called


**Async Mode:**
- Health checks run in background GenServer
- Results are cached

```elixir
# Sync mode - checks run when called
single_operation :sync_op do
  mode :sync
  health_checks [&check/0]
  handle fn health_check ->
    health_check.()  # Runs check NOW
    :done
  end
end

# Async mode - checks run in background
single_operation :async_op do
  mode :async
  health_checks [&check/0]
  handle fn health_check ->
    health_check.()  # Returns cached result
    :done
  end
end
```

## Complete Example

Here's a complete, production-ready example:

```elixir
defmodule MyApp.Backfills do
  use AdaptiveBackfill
  require Logger

  # Health check functions
  def check_database, do: DefaultPgHealthCheckers.long_waiting_queries(MyApp.Repo)
  def check_memory do
    memory = :erlang.memory(:total)
    if memory < 1_000_000_000, do: :ok, else: {:halt, :memory_high}
  end

  batch_operation :migrate_users_to_v2, initial_state: %{
    offset: 0,
    migrated: 0,
    failed: 0
  } do
    mode :async
    health_checks [&check_database/0, &check_memory/0]
    delay_between_batches 500
    timeout 60_000
    batch_size 100
    telemetry_prefix [:my_app, :backfill, :users_v2]
    
    handle_batch fn state ->
      users = MyApp.Repo.all(
        from u in User,
        where: u.version == 1,
        offset: ^state.offset,
        limit: 100
      )
      
      if Enum.empty?(users) do
        Logger.info("Migration complete: #{state.migrated} migrated, #{state.failed} failed")
        :done
      else
        {migrated, failed} = migrate_users(users)
        
        {:ok, %{
          offset: state.offset + 100,
          migrated: state.migrated + migrated,
          failed: state.failed + failed
        }}
      end
    end
    
    on_success fn state ->
      Logger.info("Batch completed: #{state.migrated} total migrated")
      Metrics.gauge("backfill.users.migrated", state.migrated)
    end
    
    on_error fn error, state ->
      Logger.error("Migration failed at offset #{state.offset}: #{inspect(error)}")
      Sentry.capture_exception(error, extra: %{state: state})
    end
    
    on_complete fn state ->
      Logger.info("Migration finished: #{state.migrated} migrated, #{state.failed} failed")
      send_slack_notification("User migration complete: #{state.migrated} users migrated")
    end
  end
  
  defp migrate_users(users) do
    Enum.reduce(users, {0, 0}, fn user, {migrated, failed} ->
      case migrate_user(user) do
        :ok -> {migrated + 1, failed}
        {:error, _} -> {migrated, failed + 1}
      end
    end)
  end
  
  defp migrate_user(user) do
    # Migration logic here
    :ok
  end
  
  defp send_slack_notification(message) do
    # Send notification
    :ok
  end
end
```

## Running Backfills

```elixir
# Run with defaults
MyApp.Backfills.migrate_users_to_v2()

# Run with custom starting point
MyApp.Backfills.migrate_users_to_v2(initial_state: %{offset: 5000, migrated: 0, failed: 0})

# Run with different timeout
MyApp.Backfills.migrate_users_to_v2(timeout: 120_000)

# Run in sync mode for testing
MyApp.Backfills.migrate_users_to_v2(mode: :sync, delay_between_batches: 0)
```

## Next Steps

- Check out [README.md](README.md) for installation and setup
- See [TESTING.md](TESTING.md) for testing strategies
- Review [CHANGELOG.md](CHANGELOG.md) for version history
- Explore the [test suite](test/) for more examples

## Checkpointing

Checkpointing allows backfills to save progress and resume from where they stopped if interrupted.

### Basic Usage

```elixir
batch_operation :migrate_users, initial_state: 0 do
  mode :async
  health_checks [&check_database/0]
  checkpoint Checkpoint.new(Checkpoint.Memory, "user_migration")
  
  handle_batch fn offset ->
    users = fetch_users(offset, 100)
    if Enum.empty?(users) do
      :done
    else
      migrate_users(users)
      {:ok, offset + 100}
    end
  end
end

# First run - processes batches and saves checkpoints
MyBackfills.migrate_users()

# If it fails, restart and it resumes from last checkpoint
MyBackfills.migrate_users()
```

### How It Works

- **On Start**: Loads checkpoint if it exists, otherwise starts from `initial_state`
- **After Each Batch**: Saves current state after successful batch
- **On Error**: Saves state before returning error
- **On Completion**: Deletes checkpoint when backfill finishes successfully

### Built-in Adapters

**Checkpoint.Memory** - In-memory storage (good for testing):
```elixir
checkpoint Checkpoint.new(Checkpoint.Memory, "my_migration")
```

**Checkpoint.ETS** - ETS-based storage (faster, concurrent):
```elixir
checkpoint Checkpoint.new(Checkpoint.ETS, "my_migration")
```

### Custom Adapters

Create your own adapter for persistent storage:

```elixir
defmodule MyApp.DBCheckpoint do
  @behaviour Checkpoint
  
  def save(name, state) do
    # Save to database
    :ok
  end
  
  def load(name) do
    # Load from database
    {:ok, state} # or {:error, :not_found}
  end
  
  def delete(name) do
    # Delete from database
    :ok
  end
end

# Use it
batch_operation :migrate, initial_state: 0 do
  checkpoint Checkpoint.new(MyApp.DBCheckpoint, "migration_v2")
  # ...
end
```

### Runtime Override

```elixir
# Disable checkpointing
MyBackfills.migrate_users(checkpoint: nil)

# Use different checkpoint
MyBackfills.migrate_users(
  checkpoint: Checkpoint.new(Checkpoint.ETS, "custom_name")
)
```
