defmodule MonitorResultEvaluatorTest do
  use ExUnit.Case

  describe "halt?/1" do
    test "returns true when any result is {:halt, reason}" do
      monitor_results = [:ok, :ok, {:halt, :timeout}, :ok]
      assert MonitorResultEvaluator.halt?(monitor_results) == true
    end

    test "returns true when first result is {:halt, reason}" do
      monitor_results = [{:halt, :error}, :ok, :ok]
      assert MonitorResultEvaluator.halt?(monitor_results) == true
    end

    test "returns true when last result is {:halt, reason}" do
      monitor_results = [:ok, :ok, {:halt, :shutdown}]
      assert MonitorResultEvaluator.halt?(monitor_results) == true
    end

    test "returns true when all results are {:halt, reason}" do
      monitor_results = [{:halt, :error1}, {:halt, :error2}, {:halt, :error3}]
      assert MonitorResultEvaluator.halt?(monitor_results) == true
    end

    test "returns false when all results are :ok" do
      monitor_results = [:ok, :ok, :ok, :ok]
      assert MonitorResultEvaluator.halt?(monitor_results) == false
    end

    test "returns false when results are empty" do
      monitor_results = []
      assert MonitorResultEvaluator.halt?(monitor_results) == false
    end

    test "returns false when results contain other tuples but no halt" do
      monitor_results = [:ok, {:error, :something}, :ok]
      assert MonitorResultEvaluator.halt?(monitor_results) == false
    end
  end
end
