defmodule HELM.Entity.Controller.EntityTest do
  use ExUnit.Case

  alias HELL.IPv6
  alias HELL.TestHelper.Random, as: HRand
  alias HELM.Entity.Controller.Entity, as: CtrlEntity
  alias HELM.Entity.Controller.EntityType, as: CtrlEntityType

  setup do
    type = HRand.string()
    ref_id = IPv6.generate([])
    payload = %{entity_type: type, reference_id: ref_id}
    {:ok, type: type, payload: payload}
  end

  test "create/1", %{type: type, payload: payload} do
    {:ok, _} = CtrlEntityType.create(type)
    assert {:ok, _} = CtrlEntity.create(payload)
  end

  describe "find/1" do
    test "success", %{type: type, payload: payload} do
      {:ok, _} = CtrlEntityType.create(type)
      {:ok, enty} = CtrlEntity.create(payload)
      assert {:ok, ^enty} = CtrlEntity.find(enty.entity_id)
    end

    test "failure" do
      assert {:error, :notfound} = CtrlEntity.find(IPv6.generate([]))
    end
  end

  test "delete/1 idempotency", %{type: type, payload: payload} do
    {:ok, _} = CtrlEntityType.create(type)
    {:ok, enty} = CtrlEntity.create(payload)
    assert :ok = CtrlEntity.delete(enty.entity_id)
    assert :ok = CtrlEntity.delete(enty.entity_id)
  end
end