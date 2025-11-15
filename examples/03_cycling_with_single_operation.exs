defmodule Examples.CyclingWithSingleOperation do
  @moduledoc """
  Using single operation for cycling/polling tasks.
  
  This example shows how to use single_operation for tasks that need to
  cycle or poll continuously until a condition is met, with health checks
  ensuring the system stays healthy during the process.
  """

  use AdaptiveBackfill

  # Poll for job completion with health monitoring
  single_operation :poll_job_status do
    mode :async
    health_checks [&check_api_health/0, &check_rate_limits/0]

    handle fn health_check ->
      job_id = "job-12345"
      IO.puts("Starting to poll job #{job_id}...")

      poll_until_complete(job_id, health_check, max_attempts: 20)
    end

    on_complete fn result ->
      case result do
        {:completed, job_id} ->
          IO.puts("✓ Job #{job_id} completed successfully!")

        {:timeout, job_id, attempts} ->
          IO.puts("✗ Job #{job_id} timed out after #{attempts} attempts")

        {:halt, reason} ->
          IO.puts("✗ Polling halted: #{inspect(reason)}")
      end
    end
  end

  # Cycle through queue processing
  single_operation :process_queue do
    mode :sync
    health_checks [&check_queue_health/0]

    handle fn health_check ->
      IO.puts("Starting queue processor...")
      process_queue_cycle(health_check, processed: 0)
    end

    on_complete fn result ->
      case result do
        {:ok, count} ->
          IO.puts("✓ Processed #{count} messages from queue")

        {:halt, reason, count} ->
          IO.puts("✗ Stopped after #{count} messages: #{inspect(reason)}")
      end
    end
  end

  # Poll until job completes or max attempts reached
  defp poll_until_complete(job_id, health_check, opts) do
    max_attempts = Keyword.get(opts, :max_attempts, 10)
    poll_loop(job_id, health_check, 0, max_attempts)
  end

  defp poll_loop(job_id, health_check, attempt, max_attempts) do
    if attempt >= max_attempts do
      {:timeout, job_id, attempt}
    else
      IO.puts("\n[Attempt #{attempt + 1}/#{max_attempts}] Checking job status...")

      # Check job status
      status = check_job_status(job_id)

      case status do
        :completed ->
          {:completed, job_id}

        :running ->
          IO.puts("  Job still running, will check again...")

          # Check health before next poll
          case health_check.() do
            :ok ->
              :timer.sleep(2000) # Wait before next poll
              poll_loop(job_id, health_check, attempt + 1, max_attempts)

            {:halt, reason} ->
              {:halt, reason}
          end

        :failed ->
          {:halt, "Job failed"}
      end
    end
  end

  defp check_job_status(job_id) do
    # Simulate API call to check job status
    :timer.sleep(500)

    # Randomly return status (more likely to be running initially)
    case :rand.uniform(10) do
      n when n <= 7 -> :running
      8 -> :completed
      _ -> :failed
    end
  end

  # Process messages from queue in a cycle
  defp process_queue_cycle(health_check, opts) do
    processed = Keyword.get(opts, :processed, 0)

    # Fetch next message from queue
    case fetch_next_message() do
      nil ->
        IO.puts("\nQueue is empty")
        {:ok, processed}

      message ->
        IO.puts("\nProcessing message #{message.id}...")
        process_message(message)

        # Check health before continuing
        case health_check.() do
          :ok ->
            # Continue processing
            process_queue_cycle(health_check, processed: processed + 1)

          {:halt, reason} ->
            {:halt, reason, processed + 1}
        end
    end
  end

  defp fetch_next_message do
    # Simulate fetching from queue (returns nil after 15 messages)
    if :rand.uniform(100) > 15 do
      nil
    else
      %{id: :rand.uniform(1000), data: "message data"}
    end
  end

  defp process_message(message) do
    IO.puts("  Processing message #{message.id}...")
    :timer.sleep(300)
    IO.puts("  ✓ Message #{message.id} processed")
  end

  defp check_api_health do
    response_time_ms = :rand.uniform(500)

    if response_time_ms > 400 do
      {:halt, "API response time too slow: #{response_time_ms}ms"}
    else
      IO.puts("  ✓ API health OK (#{response_time_ms}ms)")
      :ok
    end
  end

  defp check_rate_limits do
    remaining = :rand.uniform(100)

    if remaining < 10 do
      {:halt, "Rate limit almost exceeded: #{remaining} requests remaining"}
    else
      IO.puts("  ✓ Rate limits OK (#{remaining} remaining)")
      :ok
    end
  end

  defp check_queue_health do
    queue_depth = :rand.uniform(1000)

    if queue_depth > 900 do
      {:halt, "Queue depth too high: #{queue_depth}"}
    else
      IO.puts("  ✓ Queue health OK (depth: #{queue_depth})")
      :ok
    end
  end
end

# Run the examples
# Examples.CyclingWithSingleOperation.poll_job_status()
# Examples.CyclingWithSingleOperation.process_queue()
