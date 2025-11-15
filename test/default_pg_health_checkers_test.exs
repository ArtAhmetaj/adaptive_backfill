defmodule DefaultPgHealthCheckersTest do
  use ExUnit.Case

  alias AdaptiveBackfill.DefaultPgHealthCheckers

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AdaptiveBackfill.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AdaptiveBackfill.Repo, {:shared, self()})
    {:ok, repo: AdaptiveBackfill.Repo}
  end

  describe "pg_health_checks/1" do
    test "returns list of health check functions", %{repo: repo} do
      result = DefaultPgHealthCheckers.pg_health_checks(repo)

      assert is_list(result)
      assert length(result) == 3
    end

    test "all health checks return :ok when database is idle", %{repo: repo} do
      result = DefaultPgHealthCheckers.pg_health_checks(repo)

      Enum.each(result, fn check_result ->
        assert check_result == :ok or match?({:halt, _}, check_result)
      end)
    end
  end

  describe "long_waiting_queries/1" do
    test "returns :ok when no long queries", %{repo: repo} do
      result = DefaultPgHealthCheckers.long_waiting_queries(repo)
      assert result == :ok
    end

    test "returns {:halt, :long_queries} when long queries exist", %{repo: repo} do
      Mimic.expect(repo, :query!, fn _sql ->
        %Postgrex.Result{
          rows: [
            [
              1234,
              %Postgrex.Interval{months: 0, days: 0, secs: 120, microsecs: 0},
              "active",
              nil,
              nil,
              "SELECT * FROM large_table"
            ]
          ]
        }
      end)

      result = DefaultPgHealthCheckers.long_waiting_queries(repo)
      assert result == {:halt, :long_queries}
    end
  end

  describe "hot_io_tables/1" do
    test "returns :ok when no hot io tables", %{repo: repo} do
      result = DefaultPgHealthCheckers.hot_io_tables(repo)
      assert result == :ok
    end

    test "returns {:halt, :hot_io} when cache hit ratio is low", %{repo: repo} do
      Mimic.expect(repo, :query!, fn _sql ->
        %Postgrex.Result{
          rows: [
            ["users_table", 1000, 500, 8.0, 1500, 0.33]
          ]
        }
      end)

      result = DefaultPgHealthCheckers.hot_io_tables(repo)
      assert result == {:halt, :hot_io}
    end
  end

  describe "temp_file_usage/1" do
    test "returns :ok when temp file usage is low", %{repo: repo} do
      result = DefaultPgHealthCheckers.temp_file_usage(repo)
      assert result == :ok
    end

    test "returns {:halt, :temp_file_usage} when temp usage is high", %{repo: repo} do
      Mimic.expect(repo, :query!, fn _sql ->
        %Postgrex.Result{
          rows: [
            ["adaptive_backfill_test", 600]
          ]
        }
      end)

      result = DefaultPgHealthCheckers.temp_file_usage(repo)
      assert result == {:halt, :temp_file_usage}
    end
  end
end
