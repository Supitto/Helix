defmodule Helix.Account.Websocket.Channel.AccountTest do

  use Helix.Test.Case.Integration

  alias Helix.Websocket.Socket
  alias Helix.Entity.Action.Entity, as: EntityAction
  alias Helix.Entity.Query.Entity, as: EntityQuery
  alias Helix.Hardware.Action.Motherboard, as: MotherboardAction
  alias Helix.Server.Model.ServerType
  alias Helix.Server.Action.Server, as: ServerAction
  alias Helix.Account.Action.Session, as: SessionAction

  alias Helix.Test.Cache.Helper, as: CacheHelper
  alias Helix.Test.Entity.Factory, as: EntityFactory
  alias Helix.Test.Hardware.Factory, as: HardwareFactory
  alias Helix.Test.Server.Factory, as: ServerFactory
  alias Helix.Test.Account.Factory

  import Phoenix.ChannelTest

  @endpoint Helix.Endpoint

  setup do
    account = Factory.insert(:account)
    {:ok, token} = SessionAction.generate_token(account)
    {:ok, socket} = connect(Socket, %{token: token})
    {:ok, _, socket} = join(socket, "account:" <> to_string(account.account_id))

    {:ok, account: account, socket: socket}
  end

  defp create_server_for_entity(entity) do

    # FIXME PLEASE
    server = ServerFactory.insert(:server)
    EntityAction.link_server(entity, server.server_id)

    # I BEG YOU, SAVE ME FROM THIS EXCRUCIATING PAIN
    motherboard = HardwareFactory.insert(:motherboard)
    Enum.each(motherboard.slots, fn slot ->
      component = HardwareFactory.insert(slot.link_component_type)
      component = component.component

      MotherboardAction.link(slot, component)
    end)
    {:ok, server} = ServerAction.attach(server, motherboard.motherboard_id)

    CacheHelper.sync_test()

    server
  end

  describe "server.index" do
    test "returns all servers owned by the account", context do
      entity = EntityFactory.insert(
        :entity,
        entity_id: EntityQuery.get_entity_id(context.account))

      server_ids = Enum.map(1..5, fn _ ->
        server = create_server_for_entity(entity)

        to_string(server.server_id)
      end)

      ref = push context.socket, "server.index", %{}

      assert_reply ref, :ok, response

      received_server_ids =
        response.data.servers
        |> Enum.map(&(&1.server_id))
        |> MapSet.new()

      # TODO: improve those format checks
      assert MapSet.equal?(MapSet.new(server_ids), received_server_ids)
      assert Enum.all?(response.data.servers, fn server ->
        match?(
          %{
            server_id: _,
            server_type: _,
            password: _,
            hardware: _,
            ips: _
          },
          server)
      end)
      assert Enum.all?(response.data.servers, &(is_binary(&1.server_id)))
      assert Enum.all?(response.data.servers, fn server ->
        server.server_type in ServerType.possible_types()
      end)
      assert Enum.all?(response.data.servers, &(is_binary(&1.password)))
      assert Enum.all?(response.data.servers, fn
        %{hardware: nil} ->
          true
        %{hardware: hardware = %{}} ->
          match?(
            %{
              resources: %{
                cpu: _,
                ram: _,
                net: %{}
              },
              components: %{}
            },
            hardware)
      end)
    end
  end
end
