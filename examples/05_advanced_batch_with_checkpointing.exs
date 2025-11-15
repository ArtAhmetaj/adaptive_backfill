defmodule Examples.AdvancedBatchWithCheckpointing do
  @moduledoc """
  Advanced batch operations with checkpointing and complex state.
  
  This example demonstrates:
  - Using checkpointing to resume from failures
  - Complex state management (maps, structs)
  - Multiple health checks
  - Error handling and retry logic
  """

  use AdaptiveBackfill

  defmodule MigrationState do
    @moduledoc "Complex state for tracking migration progress"
    defstruct offset: 0,
              processed_count: 0,
              failed_ids: [],
              last_processed_id: nil,
              started_at: nil
  end

  # Complex batch operation with state tracking
  batch_operation :migrate_with_tracking,
                  initial_state: %MigrationState{started_at: DateTime.utc_now()} do
    mode :sync
    health_checks [
      &check_database_connections/0,
      &check_replication_lag/0,
      &check_disk_space/0
    ]

    # Optional: Add checkpointing
    # checkpoint adapter: MyCheckpointAdapter, name: :user_migration

    handle_batch fn state ->
      IO.puts("\n--- Batch #{div(state.offset, 100) + 1} ---")
      IO.puts("Progress: #{state.processed_count} processed, #{length(state.failed_ids)} failed")

      # Fetch users
      users = fetch_users_batch(state.offset, 100)

      if Enum.empty?(users) do
        print_final_stats(state)
        :done
      else
        # Process batch and collect results
        {successful, failed} = process_batch_with_error_handling(users)

        # Update state
        new_state = %{
          state
          | offset: state.offset + 100,
            processed_count: state.processed_count + length(successful),
            failed_ids: state.failed_ids ++ failed,
            last_processed_id: List.last(users).id
        }

        {:ok, new_state}
      end
    end

    on_complete fn result ->
      case result do
        :done ->
          IO.puts("\n✓ Migration completed!")

        {:halt, reason} ->
          IO.puts("\n✗ Migration halted: #{inspect(reason)}")
          IO.puts("You can resume from the last checkpoint")
      end
    end
  end

  # Batch operation with retry logic
  batch_operation :sync_with_retry, initial_state: {0, %{retries: %{}}} do
    mode :async
    health_checks [&check_external_api/0]

    handle_batch fn {offset, metadata} ->
      IO.puts("\n--- Syncing batch at offset #{offset} ---")

      records = fetch_records_to_sync(offset, 50)

      if Enum.empty?(records) do
        print_retry_summary(metadata.retries)
        :done
      else
        # Sync with retry logic
        {synced, failed} = sync_records_with_retry(records, metadata.retries)

        # Update retry metadata
        new_retries =
          Enum.reduce(failed, metadata.retries, fn record_id, acc ->
            retry_count = Map.get(acc, record_id, 0) + 1

            if retry_count < 3 do
              Map.put(acc, record_id, retry_count)
            else
              IO.puts("  ⚠ Record #{record_id} failed after 3 retries, skipping")
              Map.delete(acc, record_id)
            end
          end)

        new_metadata = %{metadata | retries: new_retries}
        {:ok, {offset + 50, new_metadata}}
      end
    end

    on_complete fn result ->
      case result do
        :done -> IO.puts("\n✓ Sync completed!")
        {:halt, reason} -> IO.puts("\n✗ Sync halted: #{inspect(reason)}")
      end
    end
  end

  # Batch operation with dynamic batch sizing
  batch_operation :adaptive_batch_size, initial_state: {0, 100} do
    mode :sync
    health_checks [&check_system_load/0]

    handle_batch fn {offset, batch_size} ->
      IO.puts("\n--- Processing with batch size #{batch_size} at offset #{offset} ---")

      records = fetch_records(offset, batch_size)

      if Enum.empty?(records) do
        :done
      else
        # Measure processing time
        {time_us, _result} = :timer.tc(fn -> process_records(records) end)
        time_ms = div(time_us, 1000)

        # Adjust batch size based on processing time
        new_batch_size = adjust_batch_size(batch_size, time_ms)

        IO.puts("  Processing took #{time_ms}ms, adjusting batch size to #{new_batch_size}")

        {:ok, {offset + batch_size, new_batch_size}}
      end
    end

    on_complete fn result ->
      case result do
        :done -> IO.puts("\n✓ Adaptive processing completed!")
        {:halt, reason} -> IO.puts("\n✗ Processing halted: #{inspect(reason)}")
      end
    end
  end

  # Helper functions
  defp fetch_users_batch(offset, limit) do
    if offset >= 1000 do
      []
    else
      Enum.map(1..limit, fn i ->
        %{id: offset + i, email: "user#{offset + i}@example.com", data: "data"}
      end)
    end
  end

  defp process_batch_with_error_handling(users) do
    Enum.reduce(users, {[], []}, fn user, {successful, failed} ->
      # Simulate processing with occasional failures
      if :rand.uniform(100) > 5 do
        # Success
        :timer.sleep(10)
        {[user.id | successful], failed}
      else
        # Failure
        IO.puts("  ✗ Failed to process user #{user.id}")
        {successful, [user.id | failed]}
      end
    end)
  end

  defp fetch_records_to_sync(offset, limit) do
    if offset >= 500 do
      []
    else
      Enum.map(1..limit, fn i -> %{id: offset + i} end)
    end
  end

  defp sync_records_with_retry(records, retry_map) do
    Enum.reduce(records, {[], []}, fn record, {synced, failed} ->
      retry_count = Map.get(retry_map, record.id, 0)

      # Higher success rate on retries
      success_rate = 90 + retry_count * 5

      if :rand.uniform(100) <= success_rate do
        :timer.sleep(20)
        {[record.id | synced], failed}
      else
        IO.puts("  ✗ Failed to sync record #{record.id} (attempt #{retry_count + 1})")
        {synced, [record.id | failed]}
      end
    end)
  end

  defp fetch_records(offset, limit) do
    if offset >= 800 do
      []
    else
      Enum.map(1..limit, fn i -> %{id: offset + i} end)
    end
  end

  defp process_records(records) do
    # Simulate variable processing time
    base_time = length(records) * 10
    jitter = :rand.uniform(50)
    :timer.sleep(base_time + jitter)
  end

  defp adjust_batch_size(current_size, processing_time_ms) do
    cond do
      # Too fast, increase batch size
      processing_time_ms < 500 and current_size < 500 ->
        min(current_size + 50, 500)

      # Too slow, decrease batch size
      processing_time_ms > 2000 and current_size > 50 ->
        max(current_size - 50, 50)

      # Just right
      true ->
        current_size
    end
  end

  defp print_final_stats(state) do
    duration = DateTime.diff(DateTime.utc_now(), state.started_at)

    IO.puts("\n=== Migration Statistics ===")
    IO.puts("Total processed: #{state.processed_count}")
    IO.puts("Failed: #{length(state.failed_ids)}")
    IO.puts("Duration: #{duration} seconds")

    if length(state.failed_ids) > 0 do
      IO.puts("Failed IDs: #{inspect(Enum.take(state.failed_ids, 10))}...")
    end
  end

  defp print_retry_summary(retries) do
    if map_size(retries) > 0 do
      IO.puts("\n⚠ Records still pending retry: #{map_size(retries)}")
    end
  end

  # Health check functions
  defp check_database_connections do
    connections = :rand.uniform(100)

    if connections > 80 do
      {:halt, "Database connection pool exhausted: #{connections}/100"}
    else
      IO.puts("  ✓ DB connections: #{connections}/100")
      :ok
    end
  end

  defp check_replication_lag do
    lag_seconds = :rand.uniform(60)

    if lag_seconds > 30 do
      {:halt, "Replication lag too high: #{lag_seconds}s"}
    else
      IO.puts("  ✓ Replication lag: #{lag_seconds}s")
      :ok
    end
  end

  defp check_disk_space do
    free_gb = :rand.uniform(100)

    if free_gb < 10 do
      {:halt, "Low disk space: #{free_gb}GB free"}
    else
      IO.puts("  ✓ Disk space: #{free_gb}GB free")
      :ok
    end
  end

  defp check_external_api do
    latency_ms = :rand.uniform(500)

    if latency_ms > 400 do
      {:halt, "API latency too high: #{latency_ms}ms"}
    else
      IO.puts("  ✓ API latency: #{latency_ms}ms")
      :ok
    end
  end

  defp check_system_load do
    load = :rand.uniform(100) / 100

    if load > 0.9 do
      {:halt, "System load too high: #{Float.round(load, 2)}"}
    else
      IO.puts("  ✓ System load: #{Float.round(load, 2)}")
      :ok
    end
  end
end

# Run the examples
# Examples.AdvancedBatchWithCheckpointing.migrate_with_tracking()
# Examples.AdvancedBatchWithCheckpointing.sync_with_retry()
# Examples.AdvancedBatchWithCheckpointing.adaptive_batch_size()
