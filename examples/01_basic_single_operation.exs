defmodule Examples.BasicSingleOperation do
  @moduledoc """
  Basic example of using single operation backfill.
  
  This example shows how to process a single task with health checks.
  Perfect for one-off operations or simple tasks that need monitoring.
  """

  use AdaptiveBackfill

  # Simple single operation that runs once
  single_operation :process_report do
    mode :sync
    health_checks [&check_system_health/0]

    handle fn health_check ->
      IO.puts("Starting report generation...")

      # Do the work
      generate_monthly_report()

      # Check health before finishing
      case health_check.() do
        :ok ->
          IO.puts("Report generated successfully!")
          :done

        {:halt, reason} ->
          IO.puts("Halted due to: #{inspect(reason)}")
          {:halt, reason}
      end
    end

    on_complete fn result ->
      case result do
        :done -> IO.puts("✓ Operation completed successfully")
        {:halt, reason} -> IO.puts("✗ Operation halted: #{inspect(reason)}")
      end
    end
  end

  # Health check function
  defp check_system_health do
    # Check CPU, memory, or any other system metrics
    cpu_usage = :rand.uniform(100)

    if cpu_usage > 90 do
      {:halt, "CPU usage too high: #{cpu_usage}%"}
    else
      :ok
    end
  end

  defp generate_monthly_report do
    # Simulate report generation
    :timer.sleep(1000)
    IO.puts("  - Collecting data...")
    IO.puts("  - Processing metrics...")
    IO.puts("  - Generating PDF...")
  end
end

# Run the example
# Examples.BasicSingleOperation.process_report()
