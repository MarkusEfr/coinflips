defmodule YourApp.Repo.Migrations.CreatePayoutsTable do
  use Ecto.Migration

  def change do
    create table(:payouts) do
      add(:game_id, references(:games, on_delete: :delete_all), null: false)
      add(:tx_hash, :string, null: true)
      add(:state, :string, default: "pending", null: false)

      timestamps()
    end

    create(index(:payouts, [:game_id]))
  end
end
