defmodule AllHandsSingAlong.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :google_sub, :string, null: false
      add :email, :string, null: false
      add :name, :string, null: false
      add :avatar_url, :string
      add :hosted_domain, :string
      add :last_signed_in_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:google_sub])
    create index(:users, [:email])

    alter table(:rooms) do
      add :host_user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:rooms, [:host_user_id])
  end
end
