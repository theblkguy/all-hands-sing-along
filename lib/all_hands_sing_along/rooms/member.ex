# lib/all_hands_sing_along/rooms/member.ex
defmodule AllHandsSingAlong.Rooms.Member do
  @moduledoc """
  A signed-in person who created or joined a room.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "room_members" do
    belongs_to :user, AllHandsSingAlong.Accounts.User
    belongs_to :room, AllHandsSingAlong.Rooms.Room

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(member, attrs) do
    member
    |> cast(attrs, [:user_id, :room_id])
    |> validate_required([:user_id, :room_id])
    |> unique_constraint([:user_id, :room_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:room_id)
  end
end
