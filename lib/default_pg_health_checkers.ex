defmodule DefaultPgHealthCheckers do
  @moduledoc """
  Provides default PostgreSQL health check queries that return
  :ok if everything is fine, or {:halt, reason} if issues are found.
  """

  @long_waiting_queries """
  SELECT
    pid,
    now() - query_start AS duration,
    state,
    wait_event_type,
    wait_event,
    query
  FROM pg_stat_activity
  WHERE state <> 'idle'
  ORDER BY duration DESC
  LIMIT 10;
  """

  @hot_io_tables """
  SELECT
    relname,
    heap_blks_read,
    heap_blks_hit,
    heap_blks_read * 8 / 1024 AS read_mb,
    (heap_blks_hit + heap_blks_read) AS total_accesses,
    (heap_blks_hit::float / NULLIF(heap_blks_hit + heap_blks_read, 0)) AS cache_hit_ratio
  FROM pg_statio_user_tables
  ORDER BY heap_blks_read DESC
  LIMIT 10;
  """

  @temp_file_usage """
  SELECT
    datname,
    temp_bytes / 1024 / 1024 AS temp_mb
  FROM pg_stat_database
  ORDER BY temp_bytes DESC
  LIMIT 10;
  """

  @type repo() :: module()
  @type health_result() :: :ok | {:halt, String.t()} #todo: duplicated.

  defp run_query(repo, sql) do
    repo.query!(sql)
  end

  @spec long_waiting_queries(repo()) :: health_result()
  def long_waiting_queries(repo) do
    result = run_query(repo, @long_waiting_queries)

    long_queries =
      Enum.filter(result.rows, fn [_pid, duration, _state, _type, _event, _query] ->
        {secs, _} = parse_pg_interval(duration)
        secs > 60
      end)

      parse_issue_list(long_queries, :long_queries)
  end

  @spec hot_io_tables(repo()) :: health_result()
  def hot_io_tables(repo) do
    result = run_query(repo, @hot_io_tables)

    bad_tables =
      Enum.filter(result.rows, fn [_relname, _read, _hit, _read_mb, _total, cache_hit_ratio] ->
        cache_hit_ratio < 0.5
      end)

    parse_issue_list(bad_tables, :hot_io)
  end

  @spec temp_file_usage(repo()) :: health_result()
  def temp_file_usage(repo) do
    result = run_query(repo, @temp_file_usage)

    high_temp =
      Enum.filter(result.rows, fn [_datname, temp_mb] ->
        temp_mb > 500
      end)

    parse_issue_list(high_temp, :temp_file_usage)
  end

  # helper to parse PostgreSQL interval to seconds
  defp parse_pg_interval(interval_str) do
    # "hh:mm:ss" or "hh:mm:ss.ms"
    [h, m, s] =
      interval_str
      |> to_string()
      |> String.split(":")
      |> Enum.map(&String.to_float/1)

    {h * 3600 + m * 60 + s, :seconds}
  end

  defp parse_issue_list([], _reason), do: :ok
  defp parse_issue_list(_issue, reason), do: {:halt, reason}

end
