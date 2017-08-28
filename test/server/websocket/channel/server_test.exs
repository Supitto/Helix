defmodule Helix.Server.Websocket.Channel.ServerTest do

  use Helix.Test.Case.Integration

  import Phoenix.ChannelTest
  import Helix.Test.Case.ID

  alias Helix.Entity.Query.Entity, as: EntityQuery

  alias Helix.Test.Cache.Helper, as: CacheHelper
  alias Helix.Test.Channel.Setup, as: ChannelSetup
  alias Helix.Test.Log.Helper, as: LogHelper
  alias Helix.Test.Log.Setup, as: LogSetup
  alias Helix.Test.Server.Setup, as: ServerSetup

  @moduletag :driver

  test "can connect to owned server with simple join message" do
    {socket, %{server: gateway, account: account}} =
      ChannelSetup.create_socket()

    gateway_id = to_string(gateway.server_id)
    topic = "server:" <> gateway_id

    assert {:ok, _, new_socket} =
      join(socket, topic, %{"gateway_id" => gateway_id})

    assert new_socket.assigns.access_type == :local
    assert new_socket.assigns.account == account
    assert new_socket.assigns.gateway.server_id == gateway.server_id
    assert new_socket.assigns.destination.server_id == gateway.server_id
    assert new_socket.joined
    assert new_socket.topic == topic

    CacheHelper.sync_test()
  end

  test "can not connect to a remote server without valid password" do
    {socket, %{server: gateway}} = ChannelSetup.create_socket()
    {destination, _} = ServerSetup.server()

    gateway_id = to_string(gateway.server_id)
    destination_id = to_string(destination.server_id)

    assert {:error, _} = join(
      socket,
      "server:" <> destination_id,
      %{"gateway_id" => gateway_id,
        "network_id" => "::",
        "password" => "wrongpass"})

    CacheHelper.sync_test()
  end

  test "can start connection with a remote server" do
    {socket, %{server: gateway, account: account}} =
      ChannelSetup.create_socket()
    {destination, _} = ServerSetup.server()

    gateway_id = to_string(gateway.server_id)
    destination_id = to_string(destination.server_id)
    network_id = "::"

    topic = "server:" <> destination_id
    join_msg = %{
      "gateway_id" => gateway_id,
      "network_id" => network_id,
      "password" => destination.password
    }

    assert {:ok, _, new_socket} = join(socket, topic, join_msg)

    assert new_socket.assigns.access_type == :remote
    assert new_socket.assigns.account == account
    assert_id new_socket.assigns.network_id, network_id
    assert new_socket.assigns.gateway.server_id == gateway.server_id
    assert new_socket.assigns.destination.server_id == destination.server_id
    assert new_socket.joined
    assert new_socket.topic == topic

    CacheHelper.sync_test()
  end

  @tag :slow
  test "returns files on server" do
    {socket, %{destination_files: files}} =
      ChannelSetup.join_server([destination_files: true])

    ref = push socket, "file.index", %{}

    assert_reply ref, :ok, response
    file_map = response.data.files

    expected_file_ids =
      files
      |> Enum.map(&(&1.file_id))
      |> Enum.sort()

    returned_file_ids =
      file_map
      |> Map.values()
      |> List.flatten()
      |> Enum.map(&(&1.file_id))
      |> Enum.sort()

    assert is_map(file_map)
    assert Enum.all?(Map.keys(file_map), &is_binary/1)
    assert expected_file_ids == returned_file_ids

    CacheHelper.sync_test()
  end

  describe "process.index" do
    @tag :pending
    test "fetches all processes running on destination"

    @tag :pending
    test "fetches all processes targeting destination"
  end

  describe "log.index" do
    @tag :slow
    test "fetches logs on the destination" do
      {socket, %{account: account, destination: destination}} =
        ChannelSetup.join_server()

      server_id = destination.server_id
      entity_id = EntityQuery.get_entity_id(account)

      # Create some dummy logs
      log1 = LogSetup.log!([server_id: server_id, entity_id: entity_id])
      log2 = LogSetup.log!([server_id: server_id, entity_id: entity_id])
      log3 = LogSetup.log!([server_id: server_id, entity_id: entity_id])

      # Request logs
      ref = push socket, "log.index", %{}

      # Got a valid response...
      assert_reply ref, :ok, response
      assert %{data: %{logs: logs}} = response

      # Welp, when you connect to a server it emits an event that causes a log
      # to be created on the target server. We are ignoring those logs for this
      # test because yes
      logs = Enum.reject(logs, &(&1.message =~ "logged in as root"))

      # Ensure all logs have been returned
      assert logs == LogHelper.public_view([log3, log2, log1])

      CacheHelper.sync_test()
    end
  end

  describe "log.delete" do
    @tag :pending
    test "start a process to delete target log"

    @tag :pending
    test "fails if log does not belong to target server"
  end

  describe "file.download" do
    @tag :pending
    test "initiates a process to download the specified file"

    @tag :pending
    test "returns error if the file does not belongs to target server"
  end
end
