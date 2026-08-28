# priv/repo/migrations/20260828165113_add_stem_status_to_songs.exs
defmodule AllHandsSingAlong.Repo.Migrations.AddStemStatusToSongs do
  use Ecto.Migration

  def change do
    alter table(:songs) do
      add :stem_status, :string, null: false, default: "idle"
      add :stem_error, :string
    end
  end
end
