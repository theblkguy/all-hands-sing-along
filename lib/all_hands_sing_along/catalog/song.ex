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
    field :lyric_offset_ms, :integer, default: 0
    field :stem_progress, :integer, default: 0

    field :stem_status, Ecto.Enum,
      values: [:idle, :queued, :running, :ok, :failed],
      default: :idle

    field :stem_error, :string

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
      :duration_ms,
      :lyric_offset_ms,
      :stem_progress,
      :stem_status,
      :stem_error
    ])
    |> validate_required([:title, :artist])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:artist, min: 1, max: 200)
    |> validate_length(:stem_error, max: 500)
    |> validate_number(:duration_ms, greater_than: 0)
    |> validate_number(:lyric_offset_ms,
      greater_than_or_equal_to: -15_000,
      less_than_or_equal_to: 15_000
    )
    |> validate_number(:stem_progress, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:room_id)
  end
end
