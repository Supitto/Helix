defmodule Helix.Server.Action.Component.NIC do

  alias Helix.Network.Model.Network
  alias Helix.Server.Model.Component
  alias Helix.Server.Internal.Component, as: ComponentInternal

  @typep changes_map ::
    %{
      network_id: Network.id,
      ulk: pos_integer,
      dlk: pos_integer
    }

  @typep change_transfer_speed :: %{dlk: pos_integer, ulk: pos_integer}

  @typep update_result ::
    {:ok, Component.t}
    | {:error, :internal}

  @spec update(Component.nic, term) ::
    update_result
  def update(
    nic = %Component{},
    custom = %{network_id: %Network.ID{}, ulk: _, dlk: _})
  do
    case ComponentInternal.update_custom(nic, custom) do
      {:ok, nic} ->
        {:ok, nic}

      {:error, _} ->
        {:error, :internal}
    end
  end

  @spec update_network_id(Component.nic, Network.id) ::
    update_result
  def update_network_id(nic = %Component{}, network_id = %Network.ID{}),
    do: ComponentInternal.update_custom(nic, %{network_id: network_id})

  @spec update_transfer_speed(Component.nic, change_transfer_speed) ::
    update_result
  def update_transfer_speed(nic = %Component{}, %{dlk: dlk, ulk: ulk}),
    do: ComponentInternal.update_custom(nic, %{dlk: dlk, ulk: ulk})
end
