defmodule Helix.Test.Network.Helper do

  alias Helix.Network.Model.Network
  alias Helix.Network.Query.Network, as: NetworkQuery

  def internet,
    do: NetworkQuery.internet()

  def internet_id,
    do: Network.ID.cast!("::")
end