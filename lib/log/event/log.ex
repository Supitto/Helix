defmodule Helix.Log.Event.Log do

  defmodule Created do
    @moduledoc """
    LogCreatedEvent is fired when a brand new log entry is added to the server.
    """

    alias Helix.Server.Model.Server
    alias Helix.Log.Model.Log

    @type t ::
      %__MODULE__{
        log: Log.t,
        server_id: Server.id
      }

    @enforce_keys [:server_id, :log]
    defstruct [:server_id, :log]

    @spec new(Log.t) ::
      t
    def new(log = %Log{}) do
      %__MODULE__{
        log: log,
        server_id: log.server_id
      }
    end

    defimpl Helix.Event.Notificable do

      alias HELL.ClientUtils

      @event "log_created"

      def generate_payload(event, _socket) do
        data = %{
          log_id: to_string(event.log.log_id),
          server_id: to_string(event.server_id),
          timestamp: ClientUtils.to_timestamp(event.log.creation_time),
          message: event.log.message
        }

        return = %{
          data: data,
          event: @event
        }

        {:ok, return}
      end

      def whom_to_notify(event),
        do: %{server: event.server_id}
    end
  end

  defmodule Modified do
    @moduledoc """
    LogModifiedEvent is fired when an existing log has changed (revised) or
    has been recovered.

    TODO: we'll probably want to create a LogRecovered event instead.
    """

    alias Helix.Server.Model.Server
    alias Helix.Log.Model.Log

    @type t ::
      %__MODULE__{
        log: Log.t,
        server_id: Server.id
      }

    @enforce_keys [:server_id, :log]
    defstruct [:server_id, :log]

    @spec new(Log.t) ::
      t
    def new(log = %Log{}) do
      %__MODULE__{
        log: log,
        server_id: log.server_id
      }
    end

    defimpl Helix.Event.Notificable do

      alias HELL.ClientUtils

      @event "log_modified"

      def generate_payload(event, _socket) do
        data = %{
          log_id: to_string(event.log.log_id),
          server_id: to_string(event.server_id),
          timestamp: ClientUtils.to_timestamp(event.log.creation_time),
          message: event.log.message
        }

        return = %{
          data: data,
          event: @event
        }

        {:ok, return}
      end

      def whom_to_notify(event),
        do: %{server: event.server_id}
    end
  end

  defmodule Deleted do
    @moduledoc """
    LogDeletedEvent is fired when a forged log is recovered beyond its original
    revision, leading to the log deletion.
    """

    alias Helix.Server.Model.Server
    alias Helix.Log.Model.Log

    @type t ::
      %__MODULE__{
        log: Log.t,
        server_id: Server.id
      }

    @enforce_keys [:server_id, :log]
    defstruct [:server_id, :log]

    @spec new(Log.t) ::
      t
    def new(log = %Log{}) do
      %__MODULE__{
        log: log,
        server_id: log.server_id
      }
    end

    defimpl Helix.Event.Notificable do

      @event "log_deleted"

      def generate_payload(event, _socket) do
        data = %{
          log_id: to_string(event.log.log_id),
          server_id: to_string(event.server_id)
        }

        return = %{
          data: data,
          event: @event
        }

        {:ok, return}
      end

      def whom_to_notify(event),
        do: %{server: event.server_id}
    end
  end
end
