defmodule AllHandsSingAlong.Repo.Migrations.CreateRoomMembers do
  use Ecto.Migration

  def change do
    create table(:room_members) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :room_id, references(:rooms, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:room_members, [:user_id, :room_id])
    create index(:room_members, [:room_id])

    execute(
      """
      INSERT INTO room_members (user_id, room_id, inserted_at, updated_at)
      SELECT host_user_id, id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM rooms
      WHERE host_user_id IS NOT NULL
      """,
      "DELETE FROM room_members"
    )
  end
end
