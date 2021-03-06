defmodule Helix.Cache.Internal.PopulateTest do

  use Helix.Test.Case.Integration

  import Helix.Test.Case.Cache
  import Helix.Test.Case.ID

  alias HELL.MapUtils
  alias Helix.Server.Action.Server, as: ServerAction
  alias Helix.Server.Internal.Server, as: ServerInternal
  alias Helix.Test.Cache.Helper, as: CacheHelper
  alias Helix.Cache.Internal.Builder, as: BuilderInternal
  alias Helix.Cache.Internal.Cache, as: CacheInternal
  alias Helix.Cache.Internal.Populate, as: PopulateInternal
  alias Helix.Cache.State.PurgeQueue, as: StatePurgeQueue
  alias Helix.Test.Universe.NPC.Helper, as: NPCHelper

  setup do
    CacheHelper.cache_context()
  end

  describe "populate/2" do
    test "server side-populates other caches", context do
      server_id = context.server.server_id

      {:ok, [nip]} = CacheInternal.lookup({:server, :nips}, server_id)
      {:ok, [storage_id]} = CacheInternal.lookup(
        {:server, :storages},
        server_id)

      StatePurgeQueue.sync()

      {:hit, cnip} = CacheInternal.direct_query(:network, {
        nip.network_id,
        nip.ip})

      refute cnip == nil
      assert_id cnip.server_id, server_id

      {:hit, cstorage} = CacheInternal.direct_query(:storage, storage_id)

      refute cstorage == nil
      assert_id cstorage.storage_id, storage_id

      CacheHelper.sync_test()
    end

    test "populate server with nil values", context do
      server_id = context.server.server_id

      # I could simply generate the params and call the PopulateInternal
      # `cache/1` method directly.... but we can't test private functions,
      # which makes this test (and all others on this module) totally dependent
      # on external state, side-effects, etc. ¯\_(ツ)_/¯
      # Since we can't test at the Internal level (i.e. some integration is
      # required), you will find this same test at the cache integration too

      # Note that, since we have cold cache (server is not on the cache),
      # our action won't purge/update anything.
      ServerInternal.detach(context.server)

      # See? Did not add to the purge queue
      refute StatePurgeQueue.lookup(:server, server_id)

      # And there's nothing on the DB. (Sync not needed but added for clarity)
      StatePurgeQueue.sync()
      assert_miss CacheInternal.direct_query(:server, server_id)

      # Now, if we query using the lookup/2 function, we'll populate the server
      {:ok, _} = CacheInternal.lookup(:server, server_id)
      StatePurgeQueue.sync()

      # Populated...
      assert {:hit, server} = CacheInternal.direct_query(:server, server_id)

      # With nil values
      assert_id server.server_id, server_id
      assert Enum.empty?(server.storages)
      assert Enum.empty?(server.networks)
    end

    test "pre-existing cached entries are updated", context do
      server_id = context.server.server_id

      {:ok, server1} = PopulateInternal.populate(:by_server, server_id)

      ServerAction.detach(context.server)

      {:ok, server2} = PopulateInternal.populate(:by_server, server_id)

      refute server1 == server2

      CacheHelper.sync_test()
    end

    test "storage population", context do
      {:ok, origin} = BuilderInternal.by_server(context.server.server_id)

      storage_id = Enum.random(origin.storages)

      {:ok, storage1} = PopulateInternal.populate(:by_storage, storage_id)

      {:hit, storage2} = CacheInternal.direct_query(:storage, storage_id)

      assert_id storage1.storage_id, storage2.storage_id

      CacheHelper.sync_test()
    end

    test "network population", context do
      {:ok, origin} = BuilderInternal.by_server(context.server.server_id)

      nip = Enum.random(origin.networks)

      {:ok, nip1} = PopulateInternal.populate(:by_nip, {nip.network_id, nip.ip})

      {:hit, nip2} = CacheInternal.direct_query(
        :network,
        {nip.network_id, nip.ip})

      assert_id nip1.network_id, nip2.network_id

      CacheHelper.sync_test()
    end

    test "web population" do
      {_, ip} = NPCHelper.download_center()

      {:ok, origin} = BuilderInternal.web_by_nip("::", ip)

      # Add to DB
      {:ok, web1} = PopulateInternal.populate(:web_by_nip, {"::", ip})

      # Query from db
      {:hit, web2} = CacheInternal.direct_query(
        {:web, :content},
        {"::", ip})

      assert origin.content == web1.content
      assert web1.content == MapUtils.atomize_keys(web2.content)
    end
  end

  describe "minimal cache duration" do
    test "entries have a minimal cache duration", context do
      server_id = context.server.server_id

      {:ok, [nip]} = CacheInternal.lookup({:server, :nips}, server_id)
      {:ok, [storage_id]} = CacheInternal.lookup(
        {:server, :storages},
        server_id)

      StatePurgeQueue.sync()

      {:hit, cserver} = CacheInternal.direct_query(:server, server_id)
      {:hit, cnip} = CacheInternal.direct_query(
        :network,
        {nip.network_id, nip.ip})
      {:hit, cstorage} = CacheInternal.direct_query(:storage, storage_id)

      # Ensure cache has a minimal sane duration
      # Assertions may be changed if some entry do need to live for less
      # than 10 minutes, but that's a call to re-think whether you really
      # need such low-lived cache.
      now = DateTime.utc_now()
      assert DateTime.diff(cserver.expiration_date, now) >= 600
      assert DateTime.diff(cnip.expiration_date, now) >= 600
      assert DateTime.diff(cstorage.expiration_date, now) >= 600

      CacheHelper.sync_test()
    end
  end
end
