defmodule Helix.Network.Query.WebTest do

  use Helix.Test.Case.Integration

  alias HELL.TestHelper.Random
  alias Helix.Network.Query.Web, as: WebQuery
  alias Helix.Test.Network.Helper, as: NetworkHelper
  alias Helix.Test.Universe.NPC.Helper, as: NPCHelper

  describe "browse/3" do
    test "accepts ip" do
      {_, ip} = NPCHelper.download_center()

      assert {:ok, resolution, resolved_ip} =
        WebQuery.browse(NetworkHelper.internet_id, ip, Random.ipv4())

      assert {:npc, content} = resolution
      assert resolved_ip == ip
      assert content.title
    end

    test "accepts name" do
      {dc, ip} = NPCHelper.download_center()

      assert {:ok, resolution, resolved_ip} =
        WebQuery.browse(NetworkHelper.internet_id, dc.anycast, Random.ipv4())

      assert {:npc, content} = resolution
      assert resolved_ip == ip
      assert content.title
    end

    test "fails when ip doesnt exists" do
      assert {:error, {:ip, :notfound}} ==
        WebQuery.browse(NetworkHelper.internet_id, "1.3.3.7", Random.ipv4())
    end

    test "fails when domain doesnt exists" do
      assert {:error, {:domain, :notfound}} ==
        WebQuery.browse(NetworkHelper.internet_id, "lol.com", Random.ipv4())
    end
  end

  describe "serve/2" do
    test "serves NPC pages correctly" do
      {_, ip} = NPCHelper.download_center()

      assert {:ok, page} = WebQuery.serve(NetworkHelper.internet_id(), ip)

      assert page.title
    end
  end
end
