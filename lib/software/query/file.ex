defmodule Helix.Software.Query.File do

  alias Helix.Cache.Query.Cache, as: CacheQuery
  alias Helix.Server.Model.Server
  alias Helix.Software.Model.File
  alias Helix.Software.Model.FileModule
  alias Helix.Software.Model.Storage
  alias Helix.Software.Internal.File, as: FileInternal

  @spec fetch(File.id) ::
    File.t
    | nil
  defdelegate fetch(file_id),
    to: FileInternal

  @spec fetch_best(Server.id, FileModule.name) ::
    File.t
    | nil
  @doc """
  API helper to allow querying using a server ID.

  Future enhancement: find the best software of the server by looking at *all*
  storages
  """
  def fetch_best(server_id = %Server.ID{}, module) do
    {:ok, storages} = CacheQuery.from_server_get_storages(server_id)

    fetch_best(List.first(storages), module)
  end

  @spec fetch_best(Storage.t, FileModule.name) ::
    File.t
    | nil
  @doc """
  Fetches the best software on the `storage` that matches the given `type`,
  sorting by `module` version
  """
  def fetch_best(storage, module),
    do: FileInternal.fetch_best(storage, module)

  @spec get_server_id(File.t) ::
    {:ok, Server.id}
    | {:error, :internal}
  def get_server_id(file) do
    case CacheQuery.from_storage_get_server(file.storage_id) do
      {:ok, server_id} ->
        {:ok, server_id}
      _ ->
        {:error, :internal}
    end
  end
end