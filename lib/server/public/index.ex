defmodule Helix.Server.Public.Index do

  import HELL.Macros

  alias Helix.Cache.Query.Cache, as: CacheQuery
  alias Helix.Entity.Model.Entity
  alias Helix.Entity.Query.Entity, as: EntityQuery
  alias Helix.Log.Public.Index, as: LogIndex
  alias Helix.Network.Model.Network
  alias Helix.Network.Model.Tunnel
  alias Helix.Network.Public.Index, as: NetworkIndex
  alias Helix.Network.Query.Tunnel, as: TunnelQuery
  alias Helix.Process.Public.Index, as: ProcessIndex
  alias Helix.Software.Model.Storage
  alias Helix.Software.Public.Index, as: FileIndex
  alias Helix.Server.Model.Server
  alias Helix.Server.Public.Index.Hardware, as: HardwareIndex
  alias Helix.Server.Query.Server, as: ServerQuery

  @type index ::
    %{
      player: [player_server_index],
      remote: [remote_server_index]
    }

  @typep player_server_index ::
    %{
      server: Server.t,
      nips: [Network.nip],
      endpoints: [Network.nip]
    }

  @typep remote_server_index ::
    %{
      network_id: Network.id,
      ip: Network.ip,
      password: Server.password,
      bounce: term
    }

  @type rendered_index ::
    %{
      player: [rendered_player_server_index],
      remote: [rendered_remote_server_index]
    }

  @typep rendered_player_server_index ::
    %{
      server_id: String.t,
      type: String.t,
      nips: [rendered_nip],
      endpoints: [rendered_nip]
    }

  @typep rendered_remote_server_index ::
    %{
      network_id: String.t,
      ip: String.t,
      password: String.t,
      bounce: term
    }

  @typep rendered_nip ::
    %{
      network_id: String.t,
      ip: String.t
    }

  @type gateway ::
    %{
      name: String.t,
      password: Server.password,
      nips: [Network.nip],
      logs: LogIndex.index,
      main_storage: Storage.id,
      storages: FileIndex.index,
      hardware: HardwareIndex.index,
      processes: ProcessIndex.index,
      tunnels: NetworkIndex.index,
    }

  @type rendered_gateway ::
    %{
      name: String.t,
      password: String.t,
      nips: [[String.t]],
      logs: LogIndex.rendered_index,
      main_storage: String.t,
      storages: FileIndex.rendered_index,
      hardware: HardwareIndex.rendered_index,
      processes: ProcessIndex.index,
      tunnels: NetworkIndex.rendered_index,
    }

  @type remote ::
    %{
      nips: [Network.nip],
      logs: LogIndex.index,
      main_storage: Storage.id,
      storages: FileIndex.index,
      hardware: HardwareIndex.index,
      processes: ProcessIndex.index,
      tunnels: NetworkIndex.index
    }

  @type rendered_remote ::
    %{
      nips: [[String.t]],
      logs: LogIndex.rendered_index,
      main_storage: String.t,
      storages: FileIndex.rendered_index,
      hardware: HardwareIndex.rendered_index,
      processes: ProcessIndex.index,
      tunnels: NetworkIndex.rendered_index
    }

  @spec index(Entity.t) ::
    index
  @doc """
  Returns the server index, which encompasses all other indexes residing under
  the context of server, like Logs, Filesystem, Processes, Tunnels etc.

  Called on Account bootstrap (as opposed to `gateway/2` and `remote/2`, which
  are used after the player joins a server channel)
  """
  def index(entity = %Entity{}) do
    player_servers = EntityQuery.get_servers(entity)

    # Get all endpoints (any remote server the player is SSH-ed to)
    endpoints = TunnelQuery.get_remote_endpoints(player_servers)

    Enum.reduce(player_servers, %{}, fn server_id, acc ->
      # Gets all endpoints that server is connected to
      remotes = endpoints[server_id] || []

      # Creates the remote index for this server
      remote_index = Enum.map(remotes, fn remote ->
        remote_server_index(remote)
      end)

      # Returns all endpoint nips which this server is connected to
      endpoint_nips =
        Enum.reduce(remote_index, [], fn endpoint, acc ->
          nip = %{network_id: endpoint.network_id, ip: endpoint.ip}

          acc ++ [nip]
        end)

      # Generates the player's own server index
      player_index = player_server_index(server_id, endpoint_nips)

      acc_player = Map.get(acc, :player, []) ++ [player_index]
      acc_remote = Map.get(acc, :remote, []) ++ remote_index |> Enum.uniq()

      %{
        player: acc_player,
        remote: acc_remote
      }
    end)
  end

  @spec render_index(index) ::
    rendered_index
  @doc """
  Top-level renderer for Server Index (generated by `index/1`)
  """
  def render_index(index) do
    %{
      player: Enum.map(index.player, &(render_player_server_index(&1))),
      remote: Enum.map(index.remote, &(render_remote_server_index(&1)))
    }
  end

  @spec player_server_index(Server.id, [Network.nip]) ::
    player_server_index
  defp player_server_index(server_id = %Server.ID{}, endpoint_nips) do
    server = ServerQuery.fetch(server_id)
    {:ok, nips} = CacheQuery.from_server_get_nips(server_id)

    %{
      server: server,
      nips: nips,
      endpoints: endpoint_nips
    }
  end

  @spec render_player_server_index(player_server_index) ::
    rendered_player_server_index
  defp render_player_server_index(entry = %{server: server}) do
    %{
      server_id: to_string(server.server_id),
      type: to_string(server.type),
      nips: Enum.map(entry.nips, &render_nip/1),
      endpoints: Enum.map(entry.endpoints, &render_nip/1)
    }
  end

  @spec remote_server_index(Tunnel.remote_endpoint) ::
    remote_server_index
  defp remote_server_index(remote = %{destination_id: _, network_id: _}) do
    ip = ServerQuery.get_ip(remote.destination_id, remote.network_id)
    password = ServerQuery.fetch(remote.destination_id).password

    %{
      network_id: remote.network_id,
      ip: ip,
      password: password,
      bounce: []  # TODO 256
    }
  end

  @spec render_remote_server_index(remote_server_index) ::
    rendered_remote_server_index
  defp render_remote_server_index(entry = %{password: _}) do
    %{
      network_id: to_string(entry.network_id),
      ip: entry.ip,
      password: entry.password,
      bounce: []
    }
  end

  @spec gateway(Server.t, Entity.id) ::
    gateway
  @doc """
  Generates one server entry under the context of gateway (i.e. this server
  belongs to the player).

  Scenarios:
  - On Server join, return information about the gateway
  - Resync client data with `bootstrap` request
  """
  def gateway(server = %Server{}, entity_id) do
    index = %{
      password: server.password,
      name: server.hostname,
      hardware: HardwareIndex.index(server, :local)
    }

    Map.merge(server_common(server, entity_id), index)
  end

  @spec render_gateway(gateway) ::
    rendered_gateway
  @doc """
  Renderer for `gateway/2`
  """
  def render_gateway(server) do
    partial =
      %{
        password: server.password,
        name: server.name
      }

    Map.merge(partial, render_server_common(server))
  end

  @spec remote(Server.t, Entity.id) ::
    remote
  @doc """
  Generates one server entry under the context of endpoint (i.e. this server
  does not belong to the player who made the request).

  Scenarios:
  - On Server join, return information about the endpoint
  - Resync client data with `bootstrap` request
  """
  def remote(server = %Server{}, entity_id) do
    index =
      %{
        hardware: HardwareIndex.index(server, :remote)
      }

    Map.merge(server_common(server, entity_id), index)
  end

  @spec render_remote(remote) ::
    rendered_remote
  @doc """
  Renderer for `remote/2`
  """
  def render_remote(server) do
    render_server_common(server)
  end

  @spec server_common(Server.t, Entity.id) ::
    term
  docp """
  Common values to both local and remote servers being generated.
  """
  defp server_common(server = %Server{}, entity_id) do
    {:ok, nips} = CacheQuery.from_server_get_nips(server.server_id)

    log_index = LogIndex.index(server.server_id)
    filesystem_index = FileIndex.index(server.server_id)
    tunnel_index = NetworkIndex.index(server.server_id)
    process_index = ProcessIndex.index(server.server_id, entity_id)

    main_storage_id =
      server.server_id
      |> CacheQuery.from_server_get_storages!()
      |> List.first()

    %{
      nips: nips,
      logs: log_index,
      main_storage: main_storage_id,
      storages: filesystem_index,
      processes: process_index,
      tunnels: tunnel_index
    }
  end

  @spec render_server_common(gateway | remote) ::
    term
  docp """
  Renderer for `server_common/2`.
  """
  defp render_server_common(server) do
    nips = Enum.map(server.nips, fn nip ->
      [to_string(nip.network_id), nip.ip]
    end)

    %{
      nips: nips,
      logs: LogIndex.render_index(server.logs),
      main_storage: server.main_storage |> to_string(),
      storages: FileIndex.render_index(server.storages),
      hardware: HardwareIndex.render_index(server.hardware),
      processes: server.processes,
      tunnels: NetworkIndex.render_index(server.tunnels)
    }
  end

  @spec render_nip(Network.nip) ::
    rendered_nip
  defp render_nip(nip) do
    %{
      network_id: to_string(nip.network_id),
      ip: nip.ip
    }
  end
end
