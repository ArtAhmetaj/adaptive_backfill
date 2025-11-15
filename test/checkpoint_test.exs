defmodule CheckpointTest do
  use ExUnit.Case, async: false

  alias AdaptiveBackfill.Checkpoint

  describe "Checkpoint.Memory" do
    setup do
      # Ensure the agent is started, ignore if already started
      case Checkpoint.Memory.start_link() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      Checkpoint.Memory.clear()
      :ok
    end

    test "saves and loads state" do
      state = %{offset: 100, count: 50}
      checkpoint = Checkpoint.new(Checkpoint.Memory, "test_checkpoint")

      assert :ok = Checkpoint.save(checkpoint, state)
      assert {:ok, ^state} = Checkpoint.load(checkpoint)
    end

    test "returns error when checkpoint not found" do
      checkpoint = Checkpoint.new(Checkpoint.Memory, "nonexistent")
      assert {:error, :not_found} = Checkpoint.load(checkpoint)
    end

    test "deletes checkpoint" do
      checkpoint = Checkpoint.new(Checkpoint.Memory, "test")
      Checkpoint.save(checkpoint, %{data: "value"})
      assert {:ok, _} = Checkpoint.load(checkpoint)

      assert :ok = Checkpoint.delete(checkpoint)
      assert {:error, :not_found} = Checkpoint.load(checkpoint)
    end

    test "handles multiple checkpoints" do
      cp1 = Checkpoint.new(Checkpoint.Memory, "checkpoint1")
      cp2 = Checkpoint.new(Checkpoint.Memory, "checkpoint2")

      Checkpoint.save(cp1, %{id: 1})
      Checkpoint.save(cp2, %{id: 2})

      assert {:ok, %{id: 1}} = Checkpoint.load(cp1)
      assert {:ok, %{id: 2}} = Checkpoint.load(cp2)
    end

    test "overwrites existing checkpoint" do
      checkpoint = Checkpoint.new(Checkpoint.Memory, "test")
      Checkpoint.save(checkpoint, %{version: 1})
      Checkpoint.save(checkpoint, %{version: 2})

      assert {:ok, %{version: 2}} = Checkpoint.load(checkpoint)
    end

    test "handles nil checkpoint" do
      assert :ok = Checkpoint.save(nil, %{data: "value"})
      assert {:error, :not_found} = Checkpoint.load(nil)
      assert :ok = Checkpoint.delete(nil)
    end
  end

  describe "Checkpoint.ETS" do
    setup do
      Checkpoint.ETS.start_link()
      Checkpoint.ETS.clear()
      :ok
    end

    test "saves and loads state" do
      state = %{offset: 200, items: ["a", "b", "c"]}
      checkpoint = Checkpoint.new(Checkpoint.ETS, :my_checkpoint)

      assert :ok = Checkpoint.save(checkpoint, state)
      assert {:ok, ^state} = Checkpoint.load(checkpoint)
    end

    test "returns error when checkpoint not found" do
      checkpoint = Checkpoint.new(Checkpoint.ETS, "missing")
      assert {:error, :not_found} = Checkpoint.load(checkpoint)
    end

    test "deletes checkpoint" do
      checkpoint = Checkpoint.new(Checkpoint.ETS, "test")
      Checkpoint.save(checkpoint, %{value: 123})
      assert {:ok, _} = Checkpoint.load(checkpoint)

      assert :ok = Checkpoint.delete(checkpoint)
      assert {:error, :not_found} = Checkpoint.load(checkpoint)
    end

    test "handles atom and string names" do
      cp_atom = Checkpoint.new(Checkpoint.ETS, :atom_name)
      cp_string = Checkpoint.new(Checkpoint.ETS, "string_name")

      Checkpoint.save(cp_atom, %{type: :atom})
      Checkpoint.save(cp_string, %{type: :string})

      assert {:ok, %{type: :atom}} = Checkpoint.load(cp_atom)
      assert {:ok, %{type: :string}} = Checkpoint.load(cp_string)
    end

    test "persists across multiple calls" do
      checkpoint = Checkpoint.new(Checkpoint.ETS, "persistent")
      Checkpoint.save(checkpoint, %{count: 1})

      # Simulate multiple processes accessing
      tasks =
        for _i <- 1..5 do
          Task.async(fn ->
            {:ok, state} = Checkpoint.load(checkpoint)
            state
          end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == %{count: 1}))
    end
  end

  describe "custom checkpoint adapter" do
    defmodule CustomAdapter do
      @behaviour Checkpoint
      use Agent

      def start_link do
        Agent.start_link(fn -> %{} end, name: __MODULE__)
      end

      @impl true
      def save(name, state) do
        Agent.update(
          __MODULE__,
          &Map.put(&1, name, %{state: state, timestamp: System.monotonic_time()})
        )

        :ok
      end

      @impl true
      def load(name) do
        case Agent.get(__MODULE__, &Map.get(&1, name)) do
          nil -> {:error, :not_found}
          %{state: state} -> {:ok, state}
        end
      end

      @impl true
      def delete(name) do
        Agent.update(__MODULE__, &Map.delete(&1, name))
        :ok
      end
    end

    setup do
      CustomAdapter.start_link()
      :ok
    end

    test "custom adapter works" do
      checkpoint = Checkpoint.new(CustomAdapter, "custom")

      assert :ok = Checkpoint.save(checkpoint, %{custom: true})
      assert {:ok, %{custom: true}} = Checkpoint.load(checkpoint)
      assert :ok = Checkpoint.delete(checkpoint)
      assert {:error, :not_found} = Checkpoint.load(checkpoint)
    end
  end
end
