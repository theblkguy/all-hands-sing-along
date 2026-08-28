# priv/repo/migrations/20260828150000_create_rooms_songs_queue.exs
defmodule AllHandsSingAlong.Repo.Migrations.CreateRoomsSongsQueue do
  use Ecto.Migration

  def change do
    create table(:rooms) do
      add :code, :string, null: false
      add :host_token, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:rooms, [:code])

    create table(:songs) do
      add :room_id, references(:rooms, on_delete: :delete_all)
      add :title, :string, null: false
      add :artist, :string
      add :original_path, :string
      add :instrumental_path, :string
      add :lrc_text, :text
      add :duration_ms, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:songs, [:room_id])

    create table(:queue_entries) do
      add :room_id, references(:rooms, on_delete: :delete_all), null: false
      add :song_id, references(:songs, on_delete: :nilify_all)
      add :singer_name, :string, null: false
      add :song_title, :string, null: false
      add :status, :string, null: false, default: "requested"
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:queue_entries, [:room_id, :position])
    create index(:queue_entries, [:room_id, :status])
  end
end
