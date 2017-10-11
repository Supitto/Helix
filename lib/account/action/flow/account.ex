defmodule Helix.Account.Action.Flow.Account do

  import HELF.Flow

  alias Helix.Event
  alias Helix.Entity.Action.Entity, as: EntityAction
  alias Helix.Entity.Model.Entity
  alias Helix.Server.Action.Flow.Server, as: ServerFlow
  alias Helix.Server.Model.Server
  alias Helix.Account.Action.Account, as: AccountAction
  alias Helix.Account.Model.Account

  @spec setup_account(Account.t) ::
    {:ok, %{entity: Entity.t, server: Server.t}}
    | :error
  @doc """
  Setups the input account
  """
  def setup_account(account = %Account{}) do
    flowing do
      with \
        {:ok, entity} <- EntityAction.create_from_specialization(account),
        on_fail(fn -> EntityAction.delete(entity) end),

        {:ok, server} <- ServerFlow.setup_server(entity)
      do
        {:ok, %{entity: entity, server: server}}
      else
        _err ->
          # TODO: Improve returned error
          :error
      end
    end
  end

  @spec create(Account.email, Account.username, Account.password) ::
    {:ok, Account.t}
    | {:error, Ecto.Changeset.t}
  def create(email, username, password) do
    flowing do
      with \
        {:ok, account, events} <-
          AccountAction.create(email, username, password),
        on_success(fn -> Event.emit(events) end)
      do
        {:ok, account}
      end
    end
  end
end