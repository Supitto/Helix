defmodule HELM.Hardware.Motherboard.Slot.Controller do
  import Ecto.Query

  alias HELF.{Broker, Error}
  alias HELM.Hardware
  alias HELM.Hardware.Motherboard

  def new_slot(motherboard_id, internal_id, component_type, component_id) do
    %{slot_internal_id: internal_id,
      motherboard_id: motherboard_id,
      link_component_type: component_type,
      link_component_id: component_id}
    |> Motherboard.Slot.Schema.create_changeset
    |> do_new_slot
  end

  def do_new_slot(changeset) do
    case Hardware.Repo.insert(changeset) do
      {:ok, schema} ->
        Broker.cast("event:component:motherboard:slot:created", changeset.changes.slot_id)
        {:ok, schema}
      {:error, msg} ->
        {:error, msg}
    end
  end

  def find_slot(slot_id) do
    case Hardware.Repo.get_by(Motherboard.Slot.Schema, slot_id: slot_id) do
      nil -> {:error, "Motherboard.Slot not found."}
      res -> {:ok, res}
    end
  end

  def delete_slot(slot_id) do
    case find_slot(slot_id) do
      {:ok, slot} -> do_delete_slot(slot)
      error -> error
    end
  end

  defp do_delete_slot(slot) do
    case Hardware.Repo.delete(slot) do
      {:ok, result} -> {:ok, result}
      {:error, msg} -> {:error, msg}
    end
  end
end
