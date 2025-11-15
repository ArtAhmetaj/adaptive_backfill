defmodule Examples.RealWorldPostgresExample do
  @moduledoc """
  Real-world examples using PostgreSQL with Ecto.
  
  These examples demonstrate practical use cases with actual database
  operations and the built-in PostgreSQL health checkers.
  """

  use AdaptiveBackfill
  alias AdaptiveBackfill.DefaultPgHealthCheckers

  # Assume you have a Repo module
  # alias MyApp.Repo

  # Example 1: Backfill missing data in existing records
  batch_operation :backfill_user_metadata, initial_state: 0 do
    mode :sync

    # Use built-in PostgreSQL health checkers
    health_checks DefaultPgHealthCheckers.pg_health_checks(MyApp.Repo)

    handle_batch fn offset ->
      IO.puts("\n--- Backfilling users at offset #{offset} ---")

      # Query users missing metadata using Ecto
      users =
        MyApp.Repo.all(
          from u in "users",
            where: is_nil(u.metadata),
            offset: ^offset,
            limit: 100,
            select: %{id: u.id, email: u.email}
        )

      if Enum.empty?(users) do
        IO.puts("No more users to backfill")
        :done
      else
        # Backfill metadata for each user
        Enum.each(users, fn user ->
          metadata = generate_metadata_for_user(user)

          MyApp.Repo.query!(
            "UPDATE users SET metadata = $1, updated_at = NOW() WHERE id = $2",
            [metadata, user.id]
          )
        end)

        IO.puts("  ✓ Backfilled #{length(users)} users")
        {:ok, offset + 100}
      end
    end

    on_complete fn result ->
      case result do
        :done -> IO.puts("\n✓ User metadata backfill completed!")
        {:halt, reason} -> IO.puts("\n✗ Backfill halted: #{inspect(reason)}")
      end
    end
  end

  # Example 2: Data migration between tables
  batch_operation :migrate_orders_to_new_schema, initial_state: 0 do
    mode :async
    health_checks [
      &DefaultPgHealthCheckers.long_waiting_queries/1,
      &DefaultPgHealthCheckers.hot_io_tables/1
    ]

    handle_batch fn offset ->
      IO.puts("\n--- Migrating orders at offset #{offset} ---")

      # Fetch old orders
      orders =
        MyApp.Repo.all(
          from o in "old_orders",
            where: o.migrated == false,
            offset: ^offset,
            limit: 50,
            select: %{
              id: o.id,
              user_id: o.user_id,
              total: o.total,
              items: o.items,
              created_at: o.created_at
            }
        )

      if Enum.empty?(orders) do
        :done
      else
        # Insert into new schema with transaction
        MyApp.Repo.transaction(fn ->
          Enum.each(orders, fn order ->
            # Insert into new orders table
            MyApp.Repo.query!(
              """
              INSERT INTO orders (user_id, total_amount, status, created_at)
              VALUES ($1, $2, 'completed', $3)
              RETURNING id
              """,
              [order.user_id, order.total, order.created_at]
            )
            |> then(fn %{rows: [[new_order_id]]} ->
              # Insert order items
              insert_order_items(new_order_id, order.items)

              # Mark old order as migrated
              MyApp.Repo.query!(
                "UPDATE old_orders SET migrated = true WHERE id = $1",
                [order.id]
              )
            end)
          end)
        end)

        IO.puts("  ✓ Migrated #{length(orders)} orders")
        {:ok, offset + 50}
      end
    end

    on_complete fn result ->
      case result do
        :done -> IO.puts("\n✓ Order migration completed!")
        {:halt, reason} -> IO.puts("\n✗ Migration halted: #{inspect(reason)}")
      end
    end
  end

  # Example 3: Cleanup old data with safety checks
  batch_operation :cleanup_old_logs, initial_state: 0 do
    mode :sync
    health_checks [
      &DefaultPgHealthCheckers.temp_file_usage/1,
      &check_table_bloat/0
    ]

    handle_batch fn offset ->
      cutoff_date = DateTime.add(DateTime.utc_now(), -90, :day)
      IO.puts("\n--- Cleaning logs older than #{cutoff_date} ---")

      # Delete in batches to avoid long locks
      result =
        MyApp.Repo.query!(
          """
          DELETE FROM logs
          WHERE id IN (
            SELECT id FROM logs
            WHERE created_at < $1
            ORDER BY id
            LIMIT 1000
            OFFSET $2
          )
          """,
          [cutoff_date, offset]
        )

      deleted_count = result.num_rows

      if deleted_count == 0 do
        IO.puts("No more logs to delete")
        :done
      else
        IO.puts("  ✓ Deleted #{deleted_count} log entries")
        {:ok, offset + 1000}
      end
    end

    on_complete fn result ->
      case result do
        :done ->
          IO.puts("\n✓ Log cleanup completed!")
          IO.puts("Consider running VACUUM ANALYZE on the logs table")

        {:halt, reason} ->
          IO.puts("\n✗ Cleanup halted: #{inspect(reason)}")
      end
    end
  end

  # Helper functions
  defp generate_metadata_for_user(user) do
    Jason.encode!(%{
      email_domain: String.split(user.email, "@") |> List.last(),
      backfilled_at: DateTime.utc_now(),
      version: "1.0"
    })
  end

  defp insert_order_items(order_id, items_json) do
    items = Jason.decode!(items_json)

    Enum.each(items, fn item ->
      MyApp.Repo.query!(
        """
        INSERT INTO order_items (order_id, product_id, quantity, price)
        VALUES ($1, $2, $3, $4)
        """,
        [order_id, item["product_id"], item["quantity"], item["price"]]
      )
    end)
  end

  defp check_table_bloat do
    # Custom health check for table bloat
    result =
      MyApp.Repo.query!("""
        SELECT
          schemaname,
          tablename,
          pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
        FROM pg_tables
        WHERE schemaname = 'public'
        ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
        LIMIT 1
      """)

    case result.rows do
      [[_schema, table, size]] ->
        IO.puts("  ✓ Largest table: #{table} (#{size})")
        :ok

      _ ->
        :ok
    end
  end
end

# Run the examples
# Examples.RealWorldPostgresExample.backfill_user_metadata()
# Examples.RealWorldPostgresExample.migrate_orders_to_new_schema()
# Examples.RealWorldPostgresExample.cleanup_old_logs()
