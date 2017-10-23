import Helix.Process

process Helix.Software.Process.File.Transfer do
  @moduledoc """
  SoftwareFileTransferProcess is the process responsible for transferring files
  from one storage to another. It currently implements the `download`, `upload`
  and `pftp_download` backends.

  Its process data consists basically of notifying what is the backend, and what
  storage the file is being transferred to. All other information, like which
  file is being transferred, is already present on the standard process data.
  """

  alias Helix.Software.Model.File
  alias Helix.Software.Model.Storage

  @type t :: %__MODULE__{
    type: :download | :upload,
    destination_storage_id: Storage.id,
    connection_type: :ftp | :public_ftp
  }

  @type objective ::
    %{dlk: resource_usage}
    | %{ulk: resource_usage}

  process_struct [:type, :destination_storage_id, :connection_type]

  def new(params = %{destination_storage_id: %Storage.ID{}}) do
    %__MODULE__{
      type: params.type,
      destination_storage_id: params.destination_storage_id,
      connection_type: params.connection_type
    }
  end

  # @spec objective(:download | :upload, File.t) ::
    # objective
  def objective(params = %{type: _, file: _}),
    do: set_objective params

  processable do
    @moduledoc """
    Processable handler for SoftwareFileTransferProcess

    All events emitted here are generic, i.e. they are not directly related to
    the backend using FileTransferProcess.

    For example, FileTransferProcessedEvent is emitted on conclusion, regardless
    if the backend is `download`, `upload` or `pftp_download`
    """

    alias Helix.Server.Model.Server
    alias Helix.Software.Model.Storage
    alias Helix.Software.Process.File.Transfer, as: FileTransferProcess

    alias Helix.Software.Event.File.Transfer.Aborted,
      as: FileTransferAbortedEvent
    alias Helix.Software.Event.File.Transfer.Processed,
      as: FileTransferProcessedEvent

    def dynamic_resources(%{type: :download}),
      do: [:dlk]
    def dynamic_resources(%{type: :upload}),
      do: [:ulk]

    def minimum(_),
      do: %{}

    on_kill(data, _reason) do
      reason = :killed
      {from_id, to_id} = get_servers_context(data, process)

      event =
        FileTransferAbortedEvent.new(process, data, from_id, to_id, reason)

      {:ok, [event]}
    end

    on_completion(data) do

      {from_id, to_id} = get_servers_context(data, process)
      event = FileTransferProcessedEvent.new(process, data, from_id, to_id)

      {:ok, [event]}
    end

    @spec get_servers_context(data :: term, process :: term) ::
      context :: {from_server :: Server.id, to_server :: Server.id}
    defp get_servers_context(%{type: :download}, process),
      do: {process.target_server_id, process.gateway_id}
    defp get_servers_context(%{type: :upload}, process),
      do: {process.gateway_id, process.target_server_id}

    def after_read_hook(data) do
      %FileTransferProcess{
        type: String.to_existing_atom(data.type),
        destination_storage_id: Storage.ID.cast!(data.destination_storage_id),
        connection_type: String.to_existing_atom(data.connection_type)
      }
    end
  end

  process_objective do
    @moduledoc """
    Sets the objectives to FileTransferProcess
    """

    alias Helix.Software.Factor.File, as: FileFactor

    @type params ::
      %{
        type: :download | :upload,
        file: File.t
      }

    @type factors ::
      %{
        file: %{size: FileFactor.fact_size}
      }

    @doc """
    We only need to know the file size to figure out the process objectives.
    """
    get_factors(params) do
      factor Helix.Software.Factor.File, params, only: :size
    end

    @doc """
    Uses the downlink resource during download.
    """
    dlk(%{type: :download}) do
      f.file.size
    end

    @doc """
    Uses the uplink resource during upload.
    """
    ulk(%{type: :upload}) do
      f.file.size
    end

    # Safety fallbacks
    dlk(%{type: :upload})
    ulk(%{type: :download})
  end

  executable do

    @process Helix.Software.Process.File.Transfer

    objective(_, _, params, meta) do
      %{
        type: params.type,
        file: meta.file
      }
    end

    file(_gateway, _target, _params, %{file: file}) do
      file.file_id
    end

    connection(_gateway, _target, params, _) do
      {:create, params.connection_type}
    end
  end

  process_viewable do

    @type data ::
      data_download_full
      | data_download_partial
      | data_upload

    @typep download ::
      %{
        :type => :download,
        term => term
      }

    @typep upload ::
      %{
        :type => :upload,
        term => term
      }

    @typep data_download_full ::
      %{
        connection_type: String.t,
        storage_id: String.t
      }

    @typep data_download_partial ::
      %{
        connection_type: String.t
      }

    @typep data_upload :: %{}

    @spec render_data(download, :full) :: data_download_full
    @spec render_data(download, :partial) :: data_download_partial
    @spec render_data(upload, :full | :partial) :: data_upload

    render_data(data = %{type: :download}, :full) do
      %{
        connection_type: to_string(data.connection_type),
        storage_id: to_string(data.destination_storage_id)
      }
    end
    render_data(data = %{type: :download}, :partial) do
      %{
        connection_type: to_string(data.connection_type)
      }
    end
    render_data(_, _) do
      %{}
    end
  end
end
