# Testing Setup

## Prerequisites

- Docker and Docker Compose installed
- Elixir 1.18+

## Running Tests with Database

### 1. Start PostgreSQL with Docker Compose

```bash
docker-compose up -d
```

This will start a PostgreSQL 15 container on `localhost:5432` with:
- Database: `adaptive_backfill_test`
- Username: `postgres`
- Password: `postgres`

### 2. Run Tests

```bash
mix test
```

### 3. Stop PostgreSQL

```bash
docker-compose down
```

## Test Database Configuration

The test database is configured in `config/config.exs` with:
- Host: `localhost`
- Port: `5432`
- Database: `adaptive_backfill_test`
- User: `postgres`
- Password: `postgres`

## Running Specific Tests

```bash
mix test test/default_pg_health_checkers_test.exs
```
This is the only test that needs interaction with a db.
