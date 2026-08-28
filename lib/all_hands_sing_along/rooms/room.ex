# lib/all_hands_sing_along/rooms/room.ex
defmodule AllHandsSingAlong.Rooms.Room do
  @moduledoc """
  A karaoke room identified by a short join code.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "rooms" do
    field :code, :string
    field :host_token, :string, redact: true

    has_many :songs, AllHandsSingAlong.Catalog.Song
    has_many :queue_entries, AllHandsSingAlong.Queue.Entry

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:code, :host_token])
    |> validate_required([:code, :host_token])
    |> update_change(:code, &normalize_code/1)
    |> validate_length(:code, min: 4, max: 8)
    |> unique_constraint(:code)
  end

  @spec normalize_code(String.t()) :: String.t()
  def normalize_code(code) when is_binary(code) do
    code
    |> String.trim()
    |> String.upcase()
  end
end
