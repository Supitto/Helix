defmodule Helix.Process.Action.TOP do

  import HELL.Macros

  alias Helix.Event
  alias Helix.Server.Model.Server
  alias Helix.Process.Action.Process, as: ProcessAction
  alias Helix.Process.Internal.Process, as: ProcessInternal
  alias Helix.Process.Model.Process
  alias Helix.Process.Model.TOP
  alias Helix.Process.Query.Process, as: ProcessQuery
  alias Helix.Process.Query.TOP, as: TOPQuery

  alias Helix.Process.Event.TOP.BringMeToLife, as: TOPBringMeToLifeEvent
  alias Helix.Process.Event.TOP.Recalcado, as: TOPRecalcadoEvent

  @type recalque_result ::
    {:ok, [Process.t], [TOPRecalcadoEvent.t]}
    | {:error, :resources}

  @typep relay :: Event.relay | nil
  @typep recalque_opts :: term

  @spec complete(Process.t) ::
    {:ok, [Event.t]}
    | {:error, {:process, :running}}
  @doc """
  Completes a process.

  This function may be called in two occasions:

  - When TOPBringMeToLifeEvent is fired, meaning the next process to be
    completed is supposedly finished.
  - When a TOP recalque happens and the Scheduler.forecast returns that it was
    already completed.

  Either way, a simulation is performed to make sure the process actually
  finished and, if so, a SIGTERM signal is send to the process, which will
  effectively complete it.
  """
  def complete(process) do
    case TOP.Scheduler.simulate(process) do
      {:completed, _process} ->
        ProcessAction.signal(process, :SIGTERM, %{reason: :completed})

      {:running, _process} ->
        {:error, {:process, :running}}
    end
  end

  @spec recalque(Server.id, recalque_opts) ::
    recalque_result
  @spec recalque(Process.t, recalque_opts) ::
    %{
      gateway: recalque_result,
      target: recalque_result | :noop
    }
  @doc """
  `recalque/2` performs a recalque on the server. If a Server.id is passed as
  parameter, the recalque happens in a single server. If a Process.t is passed,
  however, a recalque will be made on both the process gateway and the process
  target.

  A "recalque" is the step of recalculating the allocation of all processes
  within the given server. A recalque must be performed every time the total
  available resources on the process changes.
  """
  def recalque(process_or_server, opts \\ [])

  def recalque(%Process{gateway_id: gateway_id, target_id: gateway_id}, opts) do
    %{
      gateway: do_recalque(gateway_id, opts),
      target: :noop
    }
  end
  def recalque(%Process{gateway_id: gateway_id, target_id: target_id}, opts) do
    %{
      gateway: do_recalque(gateway_id, opts),
      target: do_recalque(target_id, opts)
    }
  end
  def recalque(server_id = %Server.ID{}, opts),
    do: do_recalque(server_id, opts)

  @spec do_recalque(Server.id, recalque_opts) ::
    recalque_result
  defp do_recalque(server_id, opts) do
    resources = TOPQuery.load_top_resources(server_id)
    processes = ProcessQuery.get_processes_on_server(server_id)

    case TOP.Allocator.allocate(server_id, resources, processes, opts) do
      {:ok, allocation_result} ->
        source = Keyword.get(opts, :source)
        processes = schedule(allocation_result, source)
        event = TOPRecalcadoEvent.new(server_id)

        {:ok, processes, [event]}

      {:error, :resources, _} ->
        {:error, :resources}
    end
  end

  @spec schedule(TOP.Allocator.allocation_successful, relay) ::
    [Process.t]
  docp """
  Top-level guide that "interprets" the Allocation results and performs the
  required actions.
  """
  defp schedule(%{allocated: processes, dropped: _dropped}, relay) do
    # Organize all processes in two groups: the local ones and the remote ones
    # A local process was started on this very server, while a remote process
    # was started somewhere else and *targets* this server.
    # (The `local?` variable was set on the Allocator).
    # This organization is useful because we can only forecast local processes.
    # (A process may be completed only on its local server; so the remote
    # processes here that are not being forecast will be forecast during *their*
    # server's TOP recalque, which should happen shortly).
    local_processes = Enum.filter(processes, &(&1.local? == true))
    remote_processes = Enum.filter(processes, &(&1.local? == false))

    # Forecast will be used to figure out which process is the next to be
    # completed. This is the first - and only - time these processes will be
    # simulated, so we have to ensure the return of `forecast/1` is served as
    # input for the Checkpoint step below.
    forecast = TOP.Scheduler.forecast(local_processes)

    # This is our new list of (local) processes. It accounts for all processes
    # that are not completed, so it contains:
    # - paused processes
    # - running processes
    # - processes awaiting allocation
    local_processes = forecast.paused ++ forecast.running

    # On a separate thread, we'll "handle" the forecast above. Basically we'll
    # track the completion date of the `next`-to-be-completed process.
    # Here we also deal with processes that were deemed already completed by the
    # simulation.
    hespawn fn -> handle_forecast(forecast, relay) end

    # Recreate the complete process list, filtering out the ones that were
    # already completed (see Forecast step above)
    processes = local_processes ++ remote_processes

    # The Checkpoint step is done to update the processes with their new
    # allocation, as well as the amount of work done previously on `processed`.
    # We'll accumulate all processes that should be updated to a list, which
    # will later be passed on to `handle_checkpoint`.
    {processes, processes_to_update} =
      Enum.reduce(processes, {[], []}, fn process, {acc_procs, acc_update} ->

        # Call `Scheduler.checkpoint/2`, which will let us know if we should
        # update the process or not.
        # Also accumulates the new process (may have changed `allocated` and
        # `last_checkpoint_time`).
        case TOP.Scheduler.checkpoint(process) do
          {true, changeset} ->
            process = Ecto.Changeset.apply_changes(changeset)
            {acc_procs ++ [process], acc_update ++ [changeset]}

          false ->
            {acc_procs ++ [process], acc_update}
        end
      end)

    # Based on the return of `checkpoint` above, we've accumulated all processes
    # that should be updated. They will be passed to `handle_checkpoint`, which
    # shall be responsible on properly handling this update in a transaction.

    # Not asynchronous because of #343; may be async if #326 allows it, but when
    # recalculating a process it MUST be synchronous to the process' local and
    # remote (if any) servers, so the TOPRecalcadoEvent is fully aware of both
    # allocs. See #326 for context & to understand how async may be used here.
    # hespawn(fn -> handle_checkpoint(processes_to_update) end)
    handle_checkpoint(processes_to_update)

    # Returns a list of all processes the new server has (excluding completed
    # ones). The processes in this list are updated with the new `allocation`,
    # `processed` and `last_checkpoint_time`.
    # Notice that this updated data hasn't been updated yet on the DB. It is
    # being performed asynchronously, in a background process.
    processes
  end

  @spec handle_forecast(TOP.Scheduler.forecast, relay) ::
    term
  docp """
  `handle_forecast` aggregates the `Scheduler.forecast/1` result and guides it
  to the corresponding handlers. Check `handle_completed/1` and `handle_next/1`
  for detailed explanation of each one.
  """
  defp handle_forecast(%{completed: completed, next: next}, relay) do
    handle_completed(completed, relay)
    handle_next(next, relay)
  end

  @spec handle_completed([Process.t], relay) ::
    term
  docp """
  `handle_completed` receives processes that according to `Schedule.forecast/1`
  have already finished. We'll then complete each one and Emit their
  corresponding events.

  For most recalques and forecasts, this function should receive an empty list.
  This is sort-of a "never should happen" scenario, but one which we are able to
  handle gracefully if it does.

  Most process completion cases are handled either by `TOPBringMeToLifeEvent` or
  calling `TOPAction.complete/1` directly once the Helix application boots up.

  Note that this function emits an event. This is "wrong", as "Action-style",
  within our architecture, are not supposed to emit events. However,
  `handle_completed` happens within a spawned process, and as such the resulting
  events cannot be sent back to the original Handler/ActionFlow caller.

  Emits event.
  """
  defp handle_completed([], _),
    do: :noop
  defp handle_completed(completed, source) do
    Enum.each(completed, fn completed_process ->
      with {:ok, events} <- complete(completed_process) do
        Event.emit(events, from: source)
      end
    end)
  end

  @spec handle_next({Process.t, Process.time_left}, relay) ::
    term
  docp """
  `handle_next` will receive the "next-to-be-completed" process, as defined by
  `Scheduler.forecast/1`. If a tuple is received, then we know there's a process
  that will be completed soon, and we'll sleep during the remaining time.
  Once the process is (supposedly) completed, TOP will receive the
  `TOPBringMeToLifeEvent`, which shall confirm the completion and actually
  complete the task.

  Emits TOPBringMeToLifeEvent.t after `time_left` seconds have elapsed.
  """
  defp handle_next({process, time_left}, _) do
    wake_me_up = TOPBringMeToLifeEvent.new(process)
    save_me = time_left * 1000 |> trunc()

    # Wakes me up inside
    Event.emit_after(wake_me_up, save_me)
  end
  defp handle_next(_, _),
    do: :noop

  @spec handle_checkpoint([Process.t]) ::
    term
  docp """
  `handle_checkpoint` is responsible for handling the result of
  `Scheduler.checkpoint/1`, called during the `recalque` above.

  It receives the *changeset* of the process, ready to be updated directly. No
  further changes are required (as far as TOP is concerned).

  These changes include the new `allocated` information, as well as the updated
  `last_checkpoint_time`.

  Ideally these changes should occur in an atomic (as in ACID-atomic) way. The
  `ProcessInternal.batch_update/1` handles the transaction details.
  """
  defp handle_checkpoint(processes),
    do: ProcessInternal.batch_update(processes)
end
