defmodule AllHandsSingAlong.Repo.Migrations.AddStemCache do
  use Ecto.Migration

  def change do
    alter table(:songs) do
      add :content_hash, :string
    end

    create index(:songs, [:content_hash])

    # One row per (original audio, guide-vocal mix). Any room that uploads the
    # same file again gets the instrumental instantly instead of re-running Demucs.
    create table(:stem_cache) do
      add :content_hash, :string, null: false
      add :vocal_mix, :float, null: false, default: 0.12
      add :instrumental_path, :string, null: false
      add :hits, :integer, null: false, default: 0
      add :source, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:stem_cache, [:content_hash, :vocal_mix])
  end
end
