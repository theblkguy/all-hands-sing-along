# lib/all_hands_sing_along/queue/entry.ex
defmodule AllHandsSingAlong.Queue.Entry do
  @moduledoc """
  One singer + song slot in a room queue.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:requested, :preparing, :ready, :now_singing, :done]

  @type status :: :requested | :preparing | :ready | :now_singing | :done
  @type t :: %__MODULE__{}

  schema "queue_entries" do
    field :singer_name, :string
    field :song_title, :string
    field :status, Ecto.Enum, values: @statuses, default: :requested
    field :position, :integer

    belongs_to :room, AllHandsSingAlong.Rooms.Room
    belongs_to :song, AllHandsSingAlong.Catalog.Song

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:room_id, :song_id, :singer_name, :song_title, :status, :position])
    |> validate_required([:room_id, :singer_name, :song_title, :status, :position])
    |> validate_length(:singer_name, min: 1, max: 80)
    |> validate_length(:song_title, min: 1, max: 200)
    |> validate_number(:position, greater_than: 0)
    |> foreign_key_constraint(:room_id)
    |> foreign_key_constraint(:song_id)
  end

  @spec status_changeset(t() | Ecto.Changeset.t(), status() | String.t()) :: Ecto.Changeset.t()
  def status_changeset(entry, status) do
    changeset(entry, %{status: status})
  end
end
