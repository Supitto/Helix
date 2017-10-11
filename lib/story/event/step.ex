defmodule Helix.Story.Event.Step do

  import Helix.Event

  event Proceeded do
    @moduledoc """
    StoryStepProceeded is fired when the Player's current step is changed,
    moving from a previous step (which may be empty) to the next one.
    """

    alias Helix.Entity.Model.Entity
    alias Helix.Story.Model.Step

    @type t ::
      %__MODULE__{
        entity_id: Entity.id,
        previous_step: Step.step_name | nil,
        next_step: Step.step_name
      }

    event_struct [:entity_id, :previous_step, :next_step]

    notify do
      @moduledoc false

      @event :story_step_proceeded

      def generate_payload(event, _socket) do
        data = %{
          previous_step: event.previous_step,
          next_step: event.next_step
        }

        {:ok, data}
      end

      @doc """
      Notifies only the player
      """
      def whom_to_notify(event),
        do: %{account: event.entity_id}
    end
  end
end