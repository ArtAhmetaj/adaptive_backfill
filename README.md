# AdaptiveBackfill

[![Tests](https://github.com/ArtAhmetaj/adaptive_backfill/workflows/Tests/badge.svg)](https://github.com/ArtAhmetaj/adaptive_backfill/actions/workflows/tests.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/adaptive_backfill.svg)](https://hex.pm/packages/adaptive_backfill)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/adaptive_backfill)

Adaptive backfill library with health checks for Elixir. Supports both single operations and batch processing with synchronous and asynchronous health monitoring.

## Features

- **Single Operation Processing**: Execute operations with health check callbacks
- **Batch Processing**: Automatically process batches with health checks between each batch
- **Sync/Async Modes**: Choose between synchronous or background health monitoring
- **PostgreSQL Health Checks**: Built-in checks for long queries, hot I/O tables, and temp file usage
- **Customizable**: Bring your own health checkers

## Installation

Add `adaptive_backfill` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:adaptive_backfill, "~> 0.1.0"}
  ]
end
```

## Usage

### DSL API (Recommended)

Define backfills using the clean DSL syntax:

```elixir
defmodule MyApp.Backfills do
  use AdaptiveBackfill

  # Single operation backfill
  single_operation :process_user do
    mode :sync
    health_checks [&check_database/0, &check_memory/0]
    
    handle fn health_check ->
      # Do some work
      user = get_next_user()
      process_user(user)
      
      # Check health before continuing
      case health_check.() do
        :ok -> :done
        {:halt, reason} -> {:halt, reason}
      end
    end
    
    on_complete fn result ->
      Logger.info("User processing completed: #{inspect(result)}")
    end
  end

  # Batch operation backfill
  batch_operation :migrate_users, initial_state: 0 do
    mode :async
    health_checks [&DefaultPgHealthCheckers.long_waiting_queries/1]
    
    handle_batch fn offset ->
      users = get_users_batch(offset, 100)
      
      if Enum.empty?(users) do
        :done
      else
        migrate_batch(users)
        {:ok, offset + 100}
      end
    end
    
    on_complete fn result ->
      Logger.info("Migration completed: #{inspect(result)}")
    end
  end
  
  defp check_database, do: :ok
  defp check_memory, do: :ok
end

# Run your backfills
MyApp.Backfills.process_user()
MyApp.Backfills.migrate_users()

# Override options at runtime
MyApp.Backfills.migrate_users(initial_state: 500, mode: :sync)
```

### Non-DSL API

You can also use the struct-based API:

```elixir
# Single operation
handle = fn health_check ->
  case health_check.() do
    :ok -> :done
    {:halt, reason} -> {:halt, reason}
  end
end

{:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, [&check/0])
AdaptiveBackfill.run(opts)

# Batch operation
handle_batch = fn state ->
  if state < 100, do: {:ok, state + 1}, else: :done
end

{:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :async, [&check/0])
AdaptiveBackfill.run(opts)
```

### PostgreSQL Health Checks

```elixir
# Use built-in PostgreSQL health checkers
health_checkers = DefaultPgHealthCheckers.pg_health_checks(MyApp.Repo)

# Or individual checks
health_checkers = [
  &DefaultPgHealthCheckers.long_waiting_queries/1,
  &DefaultPgHealthCheckers.hot_io_tables/1,
  &DefaultPgHealthCheckers.temp_file_usage/1
]
```

## Modes

### Sync Mode
Health checks are executed synchronously on-demand when called.

### Async Mode
Health checks run in the background via GenServer and provide cached results.

## Development

### Running Tests

```bash
# Start PostgreSQL
docker-compose up -d

# Run tests
mix test

# Stop PostgreSQL
docker-compose down
```

### Code Quality

```bash
# Format code
mix format

# Run linter
mix credo
```

## Publishing a New Version

1. **Update version in `mix.exs`**:
   ```elixir
   version: "0.2.0"  # Update this
   ```

2. **Update `CHANGELOG.md`** with changes:
   ```markdown
   ## [0.2.0] - 2025-11-15
   ### Added
   - New feature
   ```

3. **Commit and push changes**:
   ```bash
   git add mix.exs CHANGELOG.md
   git commit -m "Release v0.2.0"
   git push origin main
   ```

4. **Create and push a tag**:
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

### What Happens Automatically

GitHub Actions will:
- Validate tag matches mix.exs version
- Run all tests and checks
- Create GitHub Release with changelog
- Publish to Hex.pm

**Note**: The workflow will fail if the tag version doesn't match the version in `mix.exs`.

## Examples

Check out the [examples/](examples/) directory including:

- **Single operations** - One-off tasks with health monitoring
- **Pagination** - Manual pagination control
- **Cycling/polling** - Queue processing and continuous tasks
- **Batch operations** - Offset, cursor, and time-based pagination
- **Checkpointing** - Retry logic and dynamic batch sizing
- **PostgreSQL examples** - Database migrations and maintenance

See [examples/README.md](examples/README.md) for detailed documentation.

## Documentation

Documentation is available at [https://hexdocs.pm/adaptive_backfill](https://hexdocs.pm/adaptive_backfill).

## TODO / Future Improvements

### Enhanced Health Check Evaluation

The current health monitoring system uses a simple "fail-fast" approach: if **any** health check returns `{:halt, reason}`, the operation halts immediately. Production systems may need different evaluation strategies.

**Current Behavior:**
```elixir
# If ANY health check fails, the entire operation halts
health_checks [
  &check_database/0,      # Returns {:halt, :high_load}
  &check_memory/0,        # Never evaluated
  &check_disk_space/0     # Never evaluated
]
```

**Planned Improvements:**

1. **Weighted Health Checks** - Assign importance levels to different monitors
   ```elixir
   health_checks [
     {&check_database/0, weight: :critical},      # Must pass
     {&check_memory/0, weight: :warning},         # Can fail
     {&check_disk_space/0, weight: :info}         # Informational only
   ]
   ```

2. **Threshold-Based Evaluation** - Halt only when a certain number/percentage of checks fail
   ```elixir
   health_check_strategy: {:threshold, 0.5}  # Halt if >50% fail
   ```

3. **Custom Evaluation Functions** - Let users define their own logic
   ```elixir
   health_check_evaluator: fn results ->
     critical_failed = count_failed(results, :critical)
     if critical_failed > 0, do: {:halt, :critical_failure}, else: :ok
   end
   ```

4. **Graceful Degradation** - Continue with reduced functionality instead of halting
   ```elixir
   on_health_warning: fn warnings ->
     # Reduce batch size, increase delays, etc.
     {:continue, adjusted_options}
   end
   ```

## License

MIT License - see [LICENSE](LICENSE) for details.

