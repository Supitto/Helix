defmodule Helix.Server.Public.IndexTest do

  use Helix.Test.Case.Integration

  alias Helix.Entity.Model.Entity
  alias Helix.Server.Public.Index, as: ServerIndex

  alias Helix.Test.Network.Setup, as: NetworkSetup
  alias Helix.Test.Server.Setup, as: ServerSetup

  describe "index/1" do
    test "indexes player server correctly" do
      {server, %{entity: entity}} = ServerSetup.server()

      index = ServerIndex.index(entity.entity_id)

      assert length(index.player) == 1
      assert Enum.empty?(index.remote)

      server1 = List.first(index.player)

      assert server1.id == server.server_id
      refute Enum.empty?(server1.nips)
      assert Enum.empty?(server1.endpoints)
      assert server1.password == server.password
      assert server1.name
      refute Map.has_key?(server1, :bounces)
    end

    test "indexes remote connections (endpoints)" do
      {player, %{entity: entity}} = ServerSetup.server()

      {target1, _} = ServerSetup.server()
      {target2, _} = ServerSetup.server()

      tunnel1_opts =
        [gateway_id: player.server_id,
         destination_id: target1.server_id]
      NetworkSetup.connection([tunnel_opts: tunnel1_opts, type: :ssh])

      tunnel2_bounce = [target1.server_id, ServerSetup.id()]
      tunnel2_opts =
        [gateway_id: player.server_id,
         destination_id: target2.server_id,
        bounces: tunnel2_bounce]
      NetworkSetup.connection([tunnel_opts: tunnel2_opts, type: :ssh])

      index = ServerIndex.index(entity.entity_id)

      result_gateway = Enum.find(index.player, &(&1.id == player.server_id))

      endpoint_target1 =
        find_endpoint(result_gateway.endpoints, target1.server_id)
      endpoint_target2 =
        find_endpoint(result_gateway.endpoints, target2.server_id)

      assert endpoint_target1.bounces == []
      assert endpoint_target2.bounces == Enum.reverse(tunnel2_bounce)

      result_target1 = Enum.find(index.remote, &(&1.id == target1.server_id))
      result_target2 = Enum.find(index.remote, &(&1.id == target2.server_id))

      # Does not have gateway-specific data, like password or name
      censored = [:password, :name, :endpoints]
      Enum.each(censored, fn key ->
        refute Map.has_key?(result_target1, key)
        refute Map.has_key?(result_target2, key)
      end)
    end

    @tag :slow
    test "removes duplicates" do
      {gateway1, %{entity: entity}} = ServerSetup.server()
      {gateway2, _} = ServerSetup.server([entity_id: entity.entity_id])

      {target1, _} = ServerSetup.server()
      {target2, _} = ServerSetup.server()

      # Gateway1 is connected to Target1 and Target2
      g1t1_opts =
        [gateway_id: gateway1.server_id, destination_id: target1.server_id]
      NetworkSetup.connection([tunnel_opts: g1t1_opts, type: :ssh])

      g1t2_opts =
        [gateway_id: gateway1.server_id, destination_id: target2.server_id]
      NetworkSetup.connection([tunnel_opts: g1t2_opts, type: :ssh])

      # Gateway2 is connected to Target1 and Target2
      g2t1_opts =
        [gateway_id: gateway2.server_id, destination_id: target1.server_id]
      NetworkSetup.connection([tunnel_opts: g2t1_opts, type: :ssh])

      g2t2_opts =
        [gateway_id: gateway2.server_id, destination_id: target2.server_id]
      NetworkSetup.connection([tunnel_opts: g2t2_opts, type: :ssh])

      index = ServerIndex.index(entity.entity_id)

      # 2 gateway servers, 2 remote servers
      assert length(index.player) == 2
      assert length(index.remote) == 2

      result_gateway1 = Enum.find(index.player, &(&1.id == gateway1.server_id))
      result_gateway2 = Enum.find(index.player, &(&1.id == gateway2.server_id))

      gateway1_endpoints =
        Enum.sort(
          [%{server_id: target1.server_id, bounces: []},
           %{server_id: target2.server_id, bounces: []}])
      # In this context, gateway2 endpoints are the same as gateway1
      gateway2_endpoints = gateway1_endpoints

      # Endpoints are listed correctly
      assert Enum.sort(result_gateway1.endpoints) == gateway1_endpoints
      assert Enum.sort(result_gateway2.endpoints) == gateway2_endpoints
    end
  end

  describe "render_index/1" do
    test "rendered output is json friendly" do
      {player, %{entity: entity}} = ServerSetup.server()

      {target, _} = ServerSetup.server()

      tunnel_bounce = [ServerSetup.id()]
      tunnel_opts =
        [gateway_id: player.server_id,
         destination_id: target.server_id,
         bounces: tunnel_bounce]
      NetworkSetup.connection([tunnel_opts: tunnel_opts, type: :ssh])

      index = ServerIndex.index(entity.entity_id)
      rendered = ServerIndex.render_index(index)

      rendered_gateway =
        Enum.find(rendered.player, &(&1.id == to_string(player.server_id)))

      rendered_endpoint =
        Enum.find(rendered.remote, &(&1.id == to_string(target.server_id)))

      # Server ID is a string
      assert is_binary(rendered_gateway.id)
      assert is_binary(rendered_endpoint.id)

      # (Endpoint, Bounce) list is a tuple made of strings
      assert Enum.each(rendered_gateway.endpoints, fn [gateway, bounces] ->
        assert is_binary(gateway)
        assert Enum.all?(bounces, &(is_binary(&1)))
      end)

      # Nips are rendered as tuples
      Enum.each(rendered_gateway.nips, fn nip ->
        assert is_list(nip)
        assert length(nip) == 2
      end)

      Enum.each(rendered_endpoint.nips, fn nip ->
        assert is_list(nip)
        assert length(nip) == 2
      end)
    end
  end

  describe "remote_server_index/2" do
    test "indexes the remote server" do
      entity_id = Entity.ID.generate()
      {remote, _} = ServerSetup.server()

      index = ServerIndex.remote_server_index(remote.server_id, entity_id)

      assert index.id == remote.server_id
    end
  end

  describe "render_remote_server_index/1" do
    entity_id = Entity.ID.generate()
    {remote, _} = ServerSetup.server()

    index = ServerIndex.remote_server_index(remote.server_id, entity_id)
    rendered_index = ServerIndex.render_remote_server_index(index)

    assert rendered_index.id == to_string(remote.server_id)
  end

  defp find_endpoint(endpoints, server_id) do
    Enum.find(endpoints, &(&1.server_id == server_id))
  end
end