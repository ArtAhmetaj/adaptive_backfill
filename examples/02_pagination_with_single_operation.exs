defmodule Examples.PaginationWithSingleOperation do
  @moduledoc """
  Using single operation for pagination/cycling through data.
  
  This example demonstrates how to use single_operation to paginate through
  records, checking health between each page. This is useful when you want
  full control over the pagination logic.
  """

  use AdaptiveBackfill

  # Paginate through users with health checks between pages
  single_operation :paginate_users do
    mode :sync
    health_checks [&check_database_health/0, &check_memory_usage/0]

    handle fn health_check ->
      # Start pagination from offset 0
      paginate_recursive(0, 50, health_check)
    end

    on_complete fn result ->
      case result do
        {:ok, total_processed} ->
          IO.puts("✓ Successfully processed #{total_processed} users")

        {:halt, reason, processed} ->
          IO.puts("✗ Halted after processing #{processed} users: #{inspect(reason)}")
      end
    end
  end

  # Recursive pagination function
  defp paginate_recursive(offset, limit, health_check, total_processed \\ 0) do
    IO.puts("\n--- Processing page at offset #{offset} ---")

    # Fetch page of users
    users = fetch_users_page(offset, limit)

    if Enum.empty?(users) do
      # No more users, we're done
      IO.puts("No more users to process")
      {:ok, total_processed}
    else
      # Process this page
      process_users_page(users)
      new_total = total_processed + length(users)

      # Check health before continuing to next page
      case health_check.() do
        :ok ->
          IO.puts("Health check passed, continuing to next page...")
          # Continue to next page
          paginate_recursive(offset + limit, limit, health_check, new_total)

        {:halt, reason} ->
          IO.puts("Health check failed, stopping pagination")
          {:halt, reason, new_total}
      end
    end
  end

  defp fetch_users_page(offset, limit) do
    # Simulate fetching from database
    IO.puts("  Fetching users with offset=#{offset}, limit=#{limit}")
    :timer.sleep(100)

    # Simulate returning users (empty after offset 200)
    if offset >= 200 do
      []
    else
      Enum.map(1..limit, fn i ->
        %{id: offset + i, email: "user#{offset + i}@example.com"}
      end)
    end
  end

  defp process_users_page(users) do
    IO.puts("  Processing #{length(users)} users...")
    Enum.each(users, fn user ->
      # Simulate processing each user
      IO.puts("    - Processing user #{user.id}: #{user.email}")
    end)
    :timer.sleep(200)
  end

  defp check_database_health do
    # Simulate database health check
    active_connections = :rand.uniform(100)

    if active_connections > 80 do
      {:halt, "Too many database connections: #{active_connections}"}
    else
      IO.puts("  ✓ Database health OK (#{active_connections} connections)")
      :ok
    end
  end

  defp check_memory_usage do
    # Simulate memory check
    memory_mb = :rand.uniform(1000)

    if memory_mb > 900 do
      {:halt, "Memory usage too high: #{memory_mb}MB"}
    else
      IO.puts("  ✓ Memory usage OK (#{memory_mb}MB)")
      :ok
    end
  end
end

# Run the example
# Examples.PaginationWithSingleOperation.paginate_users()
