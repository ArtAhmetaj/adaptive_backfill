# AdaptiveBackfill Examples

This directory contains comprehensive examples demonstrating various use cases for the AdaptiveBackfill library.

## Examples Overview

### 1. Basic Single Operation (`01_basic_single_operation.exs`)
**Use case**: One-off tasks with health monitoring
- Simple single operation that runs once
- Synchronous health checks

**Run**: `elixir examples/01_basic_single_operation.exs`

### 2. Pagination with Single Operation (`02_pagination_with_single_operation.exs`)
**Use case**: Manual pagination control with health checks
- Paginate through records with custom logic
- Health checks between each page
- Full control over pagination behavior

**Run**: `elixir examples/02_pagination_with_single_operation.exs`

### 3. Cycling with Single Operation (`03_cycling_with_single_operation.exs`)
**Use case**: Polling, queue processing, and continuous tasks
- Poll external APIs until completion
- Process message queues continuously
- Cycle through tasks with health monitoring
- Async mode for background health checks

**Run**: `elixir examples/03_cycling_with_single_operation.exs`

### 4. Basic Batch Operation (`04_basic_batch_operation.exs`)
**Use case**: Processing large datasets efficiently
- Offset-based pagination (most common)
- Cursor-based pagination (for APIs)
- Timestamp-based pagination (for time-series data)
- Automatic health checks between batches

**Run**: `elixir examples/04_basic_batch_operation.exs`

### 5. Advanced Batch with Checkpointing (`05_advanced_batch_with_checkpointing.exs`)
**Use case**: Production-grade batch processing
- Complex state management (structs, maps)
- Checkpointing for resumable operations
- Error handling and retry logic
- Dynamic batch sizing based on performance
- Multiple health checks

**Run**: `elixir examples/05_advanced_batch_with_checkpointing.exs`

### 6. Real-World PostgreSQL Example (`06_real_world_postgres_example.exs`)
**Use case**: Database migrations and maintenance
- Backfilling missing data
- Migrating between schemas
- Cleaning up old data
- Using built-in PostgreSQL health checkers
- Ecto integration

**Run**: `elixir examples/06_real_world_postgres_example.exs`

## Health Check Patterns

### Built-in PostgreSQL Health Checks
```elixir
# Use all default checks
health_checks DefaultPgHealthCheckers.pg_health_checks(MyApp.Repo)

# Or pick specific ones
health_checks [
  &DefaultPgHealthCheckers.long_waiting_queries/1,
  &DefaultPgHealthCheckers.hot_io_tables/1,
  &DefaultPgHealthCheckers.temp_file_usage/1
]
```

### Custom Health Checks
```elixir
defp check_api_health do
  case HTTPoison.get("https://api.example.com/health") do
    {:ok, %{status_code: 200}} -> :ok
    _ -> {:halt, "API is down"}
  end
end

defp check_memory_usage do
  memory = :erlang.memory(:total)
  limit = 1_000_000_000 # 1GB

  if memory > limit do
    {:halt, "Memory usage too high: #{div(memory, 1_000_000)}MB"}
  else
    :ok
  end
end
```

## Sync vs Async Mode

### Sync Mode
- Health checks run on-demand when called
- Simpler, more predictable
- Use for short-running operations
- Lower overhead

### Async Mode
- Health checks run in background via GenServer
- Cached results returned immediately
- Use for long-running operations
- Better for expensive health checks

## Running the Examples

All examples are self-contained and can be run directly:

```bash
# Run a specific example
elixir examples/01_basic_single_operation.exs

# Or load in IEx for interactive testing
iex -S mix
iex> Code.require_file("examples/01_basic_single_operation.exs")
iex> Examples.BasicSingleOperation.process_report()
```

## Adapting Examples for Your Use Case

1. **Replace mock data sources** with your actual database queries or API calls
2. **Customize health checks** based on your infrastructure
3. **Adjust batch sizes** based on your data and performance requirements
4. **Add checkpointing** for long-running operations that need to be resumable
5. **Implement proper error handling** for production use

## Common Patterns

### Pattern 1: Offset-Based Pagination
```elixir
batch_operation :process_users, initial_state: 0 do
  handle_batch fn offset ->
    users = fetch_users(offset, 100)
    if Enum.empty?(users), do: :done, else: {:ok, offset + 100}
  end
end
```

### Pattern 2: Cursor-Based Pagination
```elixir
batch_operation :sync_data, initial_state: nil do
  handle_batch fn cursor ->
    {data, next_cursor} = fetch_from_api(cursor)
    if next_cursor, do: {:ok, next_cursor}, else: :done
  end
end
```

### Pattern 3: Time-Based Processing
```elixir
batch_operation :process_logs, initial_state: ~U[2020-01-01 00:00:00Z] do
  handle_batch fn start_time ->
    end_time = DateTime.add(start_time, 1, :day)
    logs = fetch_logs(start_time, end_time)
    if logs, do: {:ok, end_time}, else: :done
  end
end
```

## Need Help?

- Check the main [README.md](../README.md) for API documentation
- Read [USING.md](../USING.md) for detailed usage guide
- See [TESTING.md](../TESTING.md) for testing strategies
- Open an issue on GitHub for questions or bugs
