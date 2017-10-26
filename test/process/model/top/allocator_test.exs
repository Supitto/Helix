defmodule Helix.Process.Model.Top.AllocatorTest do

  use ExUnit.Case, async: true

  import Helix.Test.Process.Macros

  alias Helix.Process.Model.Process
  alias Helix.Process.Model.TOP.Allocator, as: TOPAllocator

  alias Helix.Test.Process.Setup.TOP, as: TOPSetup

  alias HELL.TestHelper.Random

  describe "allocate/2" do

    test "one process; all resources" do
      {total_resources, _} = TOPSetup.Resources.resources()

      [proc1] =
        TOPSetup.fake_process(
          total_resources: total_resources, dynamic: [:cpu, :ram, :ulk, :dlk]
        )

      assert [{returned_proc, alloc}] =
        TOPAllocator.allocate(total_resources, [proc1])

      assert returned_proc == proc1

      # Allocation of one process will receive all available resources
      assert_resource alloc.cpu, total_resources.cpu
      assert_resource alloc.ram, total_resources.ram
      assert_resource alloc.dlk, total_resources.dlk
      assert_resource alloc.ulk, total_resources.ulk
    end

    test "two processes; non-overlapping dynamic; non-overlapping static" do
      {total_resources, _} = TOPSetup.Resources.resources()

      [proc1, proc2, proc3, proc4] =
        TOPSetup.fake_process(total_resources: total_resources, total: 4)

      # Proc1 has dynamic CPU resource and does not use any other static res
      proc1 = %{proc1| dynamic: [:cpu]}
      proc1 = put_in(proc1, [:static, :running, :ram], 0)
      proc1 = put_in(proc1, [:static, :running, :ulk], 0)
      proc1 = put_in(proc1, [:static, :running, :dlk], 0)

      # Proc2 has dynamic RAM resource and does not use any other static res
      proc2 = %{proc2| dynamic: [:ram]}
      proc2 = put_in(proc2, [:static, :running, :cpu], 0)
      proc2 = put_in(proc2, [:static, :running, :ulk], 0)
      proc2 = put_in(proc2, [:static, :running, :dlk], 0)

      # Proc3 has dynamic ULK resource and does not use any other static res
      proc3 = %{proc3| dynamic: [:ulk]}
      proc3 = put_in(proc3, [:static, :running, :cpu], 0)
      proc3 = put_in(proc3, [:static, :running, :ram], 0)
      proc3 = put_in(proc3, [:static, :running, :dlk], 0)

      # Proc4 has dynamic DLK resource and does not use any other static res
      proc4 = %{proc4| dynamic: [:dlk]}
      proc4 = put_in(proc4, [:static, :running, :cpu], 0)
      proc4 = put_in(proc4, [:static, :running, :ram], 0)
      proc4 = put_in(proc4, [:static, :running, :ulk], 0)

      procs = [proc1, proc2, proc3, proc4]

      assert [{p1, alloc1}, {p2, alloc2}, {p3, alloc3}, {p4, alloc4}] =
        TOPAllocator.allocate(total_resources, procs)

      assert p1 == proc1
      assert p2 == proc2
      assert p3 == proc3
      assert p4 == proc4

      # Allocated all available server resources
      assert_resource alloc1.cpu, total_resources.cpu
      assert_resource alloc1.ram, 0
      assert_resource alloc1.ulk, 0
      assert_resource alloc1.dlk, 0

      assert_resource alloc2.cpu, 0
      assert_resource alloc2.ram, total_resources.ram
      assert_resource alloc2.ulk, 0
      assert_resource alloc2.dlk, 0

      assert_resource alloc3.cpu, 0
      assert_resource alloc3.ram, 0
      assert_resource alloc3.ulk, total_resources.ulk
      assert_resource alloc3.dlk, 0

      assert_resource alloc4.cpu, 0
      assert_resource alloc4.ram, 0
      assert_resource alloc4.ulk, 0
      assert_resource alloc4.dlk, total_resources.dlk
    end

    test "two processes; non-overlapping dynamic; overlapping static" do
      {total_resources, _} = TOPSetup.Resources.resources()

      # Note that, by default, all processes have *some* static res assigned to
      # it (except dlk/ulk).
      [proc1, proc2] =
        TOPSetup.fake_process(total_resources: total_resources, total: 2)

      # `proc1` will be dynamic only on CPU; `proc2`, on RAM
      proc1 = %{proc1| dynamic: [:cpu]}
      proc2 = %{proc2| dynamic: [:ram]}

      procs = [proc1, proc2]

      assert [{p1, alloc1}, {p2, alloc2}] =
        TOPAllocator.allocate(total_resources, procs)

      assert p1 == proc1
      assert p2 == proc2

      # Allocated all available server resources
      assert_resource alloc1.cpu + alloc2.cpu, total_resources.cpu
      assert_resource alloc1.ram + alloc2.ram, total_resources.ram
    end

    test "two processes; overlapping dynamic and static resources" do
      {total_resources, _} = TOPSetup.Resources.resources()

      procs = TOPSetup.fake_process(
        total_resources: total_resources, total: 2, dynamic: [:cpu, :ram]
      )

      assert [{_p1, alloc1}, {_p2, alloc2}] =
        TOPAllocator.allocate(total_resources, procs)

      # Allocated all available server resources
      assert_resource alloc1.cpu + alloc2.cpu, total_resources.cpu
      assert_resource alloc1.ram + alloc2.ram, total_resources.ram
    end

    test "n processes; overlapping everywhere" do
      {total_resources, _} = TOPSetup.Resources.resources()
      initial = Process.Resources.initial()

      # We'll simulate the allocation of 50..100 processes (it takes 3ms!)
      n = Random.number(min: 50, max: 100)

      procs =
        TOPSetup.fake_process(
          total_resources: total_resources, total: n, dynamic: [:cpu, :ram]
        )

      # Allocates all `n` processes
      results = TOPAllocator.allocate(total_resources, procs)

      accumulated_resources =
        Enum.reduce(results, initial, fn {_process, alloc}, acc ->
          Process.Resources.sum(acc, alloc)
        end)

      # The accumulation (sum) of all processes' resources must be equal to the
      # total server's resources.
      assert_resource accumulated_resources.cpu, total_resources.cpu
      assert_resource accumulated_resources.ram, total_resources.ram
    end

    test "rejects when there would be resource overflow (on static alloc)" do
      initial = Process.Resources.initial()

      [proc] = TOPSetup.fake_process()

      assert {:error, reason, _} = TOPAllocator.allocate(initial, [proc])
      assert reason == :resources
    end

    @tag :pending
    test "on overflow, returns reference to overflowed process"

    @tag :pending
    test "picks the heaviest process among multiple overflowing processes"
  end
end
