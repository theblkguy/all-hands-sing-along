defmodule AllHandsSingAlong.Repo.Migrations.AddLyricOffsetAndStemProgressToSongs do
  use Ecto.Migration

  def change do
    alter table(:songs) do
      add :lyric_offset_ms, :integer, null: false, default: 0
      add :stem_progress, :integer, null: false, default: 0
    end
  end
end
