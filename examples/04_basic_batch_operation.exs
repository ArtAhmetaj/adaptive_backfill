defmodule Examples.BasicBatchOperation do
  @moduledoc """
  Basic batch operation examples.
  
  Batch operations automatically handle pagination and health checks between
  batches. This is the recommended approach for processing large datasets.
  """

  use AdaptiveBackfill

  # Simple batch processing with offset-based pagination
  batch_operation :migrate_users, initial_state: 0 do
    mode :sync
    health_checks [&check_database/0]

    handle_batch fn offset ->
      IO.puts("\n--- Processing batch at offset #{offset} ---")

      # Fetch batch of users
      users = fetch_users(offset, 100)

      if Enum.empty?(users) do
        IO.puts("No more users to migrate")
        :done
      else
        # Process the batch
        migrate_users_batch(users)

        # Return next offset
        {:ok, offset + 100}
      end
    end

    on_complete fn result ->
      case result do
        :done ->
          IO.puts("\n✓ All users migrated successfully!")

        {:halt, reason} ->
          IO.puts("\n✗ Migration halted: #{inspect(reason)}")
      end
    end
  end

  # Batch processing with cursor-based pagination
  batch_operation :sync_orders, initial_state: nil do
    mode :async
    health_checks [&check_api_health/0, &check_database/0]

    handle_batch fn cursor ->
      IO.puts("\n--- Syncing orders batch (cursor: #{inspect(cursor)}) ---")

      # Fetch from external API with cursor
      {orders, next_cursor} = fetch_orders_from_api(cursor)

      if Enum.empty?(orders) do
        IO.puts("No more orders to sync")
        :done
      else
        # Sync orders to database
        sync_orders_to_db(orders)

        if next_cursor do
          {:ok, next_cursor}
        else
          :done
        end
      end
    end

    on_complete fn result ->
      case result do
        :done ->
          IO.puts("\n✓ All orders synced!")

        {:halt, reason} ->
          IO.puts("\n✗ Sync halted: #{inspect(reason)}")
      end
    end
  end

  # Batch processing with timestamp-based pagination
  batch_operation :archive_old_logs, initial_state: ~U[2020-01-01 00:00:00Z] do
    mode :sync
    health_checks [&check_storage/0]

    handle_batch fn start_date ->
      # Process one month at a time
      end_date = DateTime.add(start_date, 30, :day)
      IO.puts("\n--- Archiving logs from #{start_date} to #{end_date} ---")

      # Fetch logs in date range
      logs = fetch_logs_in_range(start_date, end_date)

      if Enum.empty?(logs) do
        IO.puts("No more logs to archive")
        :done
      else
        # Archive the logs
        archive_logs(logs)

        # Check if we've reached the present
        now = DateTime.utc_now()

        if DateTime.compare(end_date, now) == :lt do
          {:ok, end_date}
        else
          :done
        end
      end
    end

    on_complete fn result ->
      case result do
        :done ->
          IO.puts("\n✓ All old logs archived!")

        {:halt, reason} ->
          IO.puts("\n✗ Archival halted: #{inspect(reason)}")
      end
    end
  end

  # Helper functions
  defp fetch_users(offset, limit) do
    IO.puts("  Fetching users with offset=#{offset}, limit=#{limit}")
    :timer.sleep(100)

    if offset >= 500 do
      []
    else
      Enum.map(1..limit, fn i ->
        %{id: offset + i, name: "User #{offset + i}"}
      end)
    end
  end

  defp migrate_users_batch(users) do
    IO.puts("  Migrating #{length(users)} users...")
    Enum.each(users, fn user ->
      # Simulate migration work
      :timer.sleep(10)
    end)
    IO.puts("  ✓ Batch migrated")
  end

  defp fetch_orders_from_api(cursor) do
    IO.puts("  Fetching orders from API...")
    :timer.sleep(200)

    # Simulate API response
    cursor_num = if cursor, do: String.to_integer(cursor), else: 0

    if cursor_num >= 300 do
      {[], nil}
    else
      orders =
        Enum.map(1..50, fn i ->
          %{id: cursor_num + i, total: :rand.uniform(1000)}
        end)

      next_cursor = Integer.to_string(cursor_num + 50)
      {orders, next_cursor}
    end
  end

  defp sync_orders_to_db(orders) do
    IO.puts("  Syncing #{length(orders)} orders to database...")
    :timer.sleep(150)
    IO.puts("  ✓ Orders synced")
  end

  defp fetch_logs_in_range(start_date, end_date) do
    IO.puts("  Fetching logs...")
    :timer.sleep(100)

    # Simulate fetching logs
    now = DateTime.utc_now()

    if DateTime.compare(start_date, now) == :gt do
      []
    else
      Enum.map(1..100, fn i ->
        %{id: i, timestamp: start_date, message: "Log entry #{i}"}
      end)
    end
  end

  defp archive_logs(logs) do
    IO.puts("  Archiving #{length(logs)} logs...")
    :timer.sleep(200)
    IO.puts("  ✓ Logs archived")
  end

  defp check_database do
    connections = :rand.uniform(50)

    if connections > 45 do
      {:halt, "Too many database connections: #{connections}"}
    else
      IO.puts("  ✓ Database OK (#{connections} connections)")
      :ok
    end
  end

  defp check_api_health do
    status = if :rand.uniform(100) > 95, do: :down, else: :up

    if status == :down do
      {:halt, "External API is down"}
    else
      IO.puts("  ✓ API OK")
      :ok
    end
  end

  defp check_storage do
    usage_percent = :rand.uniform(100)

    if usage_percent > 95 do
      {:halt, "Storage almost full: #{usage_percent}%"}
    else
      IO.puts("  ✓ Storage OK (#{usage_percent}% used)")
      :ok
    end
  end
end

# Run the examples
# Examples.BasicBatchOperation.migrate_users()
# Examples.BasicBatchOperation.sync_orders()
# Examples.BasicBatchOperation.archive_old_logs()
