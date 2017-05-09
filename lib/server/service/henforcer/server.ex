defmodule Helix.Server.Service.Henforcer.Server do

  alias Helix.Hardware.Service.API.Component, as: ComponentAPI
  alias Helix.Hardware.Service.API.Motherboard, as: MotherboardAPI
  alias Helix.Server.Model.Server
  alias Helix.Server.Controller.Server, as: Controller

  # TODO: rename functions. since the context is servers, it's a bit redundant
  #   for the functions to start with server_*

  @spec server_exists?(HELL.PK.t) ::
    boolean
  def server_exists?(server) do
    # TODO: Use a count(server_id) to waste less resources
    !!Controller.fetch(server)
  end

  @spec server_assembled?(HELL.PK.t) ::
    boolean
  def server_assembled?(server) do
    with \
      server = %Server{} <- Controller.fetch(server)
    do
      not is_nil(server.motherboard_id)
    else
      _ ->
        false
    end
  end

  @doc """
  Checks if a server has what is needed to provide minimum functionality

  This will check that:
  - The server has a motherboard assembled
  - The motherboard has a HDD assembled
  - The motherboard has a CPU assembled
  - The motherboard has a RAM assembled
  """
  def functioning?(server) do
    with \
      server = %Server{} <- Controller.fetch(server),
      motherboard when not is_nil(motherboard) <- server.motherboard_id,
      motherboard = %{} <- ComponentAPI.fetch(motherboard),
      motherboard = MotherboardAPI.fetch!(motherboard),
      slots = [_|_] <- MotherboardAPI.get_slots(motherboard),
      hdds = [_|_] <- Enum.filter(slots, &(&1.link_component_type == :hdd)),
      true <- Enum.any?(hdds, &(not is_nil(&1.link_component_id))),
      rams = [_|_] <- Enum.filter(slots, &(&1.link_component_type == :ram)),
      true <- Enum.any?(rams, &(not is_nil(&1.link_component_id))),
      cpus = [_|_] <- Enum.filter(slots, &(&1.link_component_type == :cpu)),
      true <- Enum.any?(cpus, &(not is_nil(&1.link_component_id)))
    do
      true
    else
      _ ->
        false
    end
  end
end