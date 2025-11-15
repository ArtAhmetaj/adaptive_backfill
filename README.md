# AdaptiveBackfill

[![CI](https://github.com/YOUR_USERNAME/adaptive_backfill/workflows/Tests/badge.svg)](https://github.com/YOUR_USERNAME/adaptive_backfill/actions)
[![Hex.pm](https://img.shields.io/hexpm/v/adaptive_backfill.svg)](https://hex.pm/packages/adaptive_backfill)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/adaptive_backfill)

Adaptive backfill library with health checks for Elixir. Supports both single operations and batch processing with synchronous and asynchronous health monitoring.

## Features

- **Single Operation Processing**: Execute operations with health check callbacks
- **Batch Processing**: Automatically process batches with health checks between each batch
- **Sync/Async Modes**: Choose between synchronous or background health monitoring
- **PostgreSQL Health Checks**: Built-in checks for long queries, hot I/O tables, and temp file usage
- **Customizable**: Bring your own health checkers
- **Well-tested**: 69 tests with comprehensive coverage

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

### Single Operation Example

```elixir
# Define your operation with a health check callback
handle = fn health_check ->
  # Do some work
  process_record()
  
  # Check health before continuing
  case health_check.() do
    :ok -> :done
    {:halt, reason} -> {:halt, reason}
  end
end

# Define health checkers
health_checkers = [
  fn -> check_database_health() end,
  fn -> check_memory_usage() end
]

# Create options and run
{:ok, opts} = SingleOperationOptions.new(handle, nil, :sync, health_checkers)
AdaptiveBackfill.run(opts)
```

### Batch Operation Example

```elixir
# Define your batch handler
handle_batch = fn
  state when state < 100 ->
    # Process batch
    process_batch(state)
    {:ok, state + 1}
  _ ->
    :done
end

# Health checks run automatically between batches
health_checkers = [DefaultPgHealthCheckers.long_waiting_queries(MyApp.Repo)]

# Create options and run
{:ok, opts} = BatchOperationOptions.new(0, handle_batch, nil, :async, health_checkers)
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

### Automated (Recommended)

Use the Makefile commands to automate version bumping:

```bash
# Bump patch version (0.1.0 -> 0.1.1)
make bump-patch

# Bump minor version (0.1.0 -> 0.2.0)
make bump-minor

# Bump major version (0.1.0 -> 1.0.0)
make bump-major

# Or specify exact version
make bump VERSION=0.2.0
```

This will:
1. Update `mix.exs` version
2. Add a new section to `CHANGELOG.md` with today's date
3. Show you the next steps

Then:

```bash
# 1. Edit CHANGELOG.md to add your changes
vim CHANGELOG.md

# 2. Review changes
git diff

# 3. Create release (runs tests, commits, tags)
make release

# 4. Push to trigger CI/CD
make release-push
```

### Manual Process

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

## Documentation

Documentation is available at [https://hexdocs.pm/adaptive_backfill](https://hexdocs.pm/adaptive_backfill).

## License

MIT License - see [LICENSE](LICENSE) for details.

