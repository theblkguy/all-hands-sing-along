# lib/all_hands_sing_along/catalog/song.ex
defmodule AllHandsSingAlong.Catalog.Song do
  @moduledoc """
  An uploaded or fixture track, with optional instrumental and LRC.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "songs" do
    field :title, :string
    field :artist, :string
    field :original_path, :string
    field :instrumental_path, :string
    field :lrc_text, :string
    field :duration_ms, :integer

    belongs_to :room, AllHandsSingAlong.Rooms.Room

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(song, attrs) do
    song
    |> cast(attrs, [
      :room_id,
      :title,
      :artist,
      :original_path,
      :instrumental_path,
      :lrc_text,
      :duration_ms
    ])
    |> validate_required([:title, :artist])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:artist, min: 1, max: 200)
    |> validate_number(:duration_ms, greater_than: 0)
    |> foreign_key_constraint(:room_id)
  end
end
