defmodule AllHandsSingAlong.Repo.Migrations.AddUsernamesAndQueueUserIds do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :username, :string
    end

    create unique_index(:users, ["lower(username)"],
             name: :users_username_lower_index,
             where: "username IS NOT NULL"
           )

    alter table(:queue_entries) do
      add :user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:queue_entries, [:user_id])
  end
end
