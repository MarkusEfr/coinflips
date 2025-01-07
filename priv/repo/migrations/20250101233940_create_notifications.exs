defmodule Coinflips.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add(:wallet_address, :string, null: false)
      add(:title, :string, null: false)
      add(:message, :text, null: false)
      add(:unread?, :boolean, default: true, null: false)
      add(:game_id, references(:games, on_delete: :delete_all))

      timestamps()
    end

    create(index(:notifications, [:wallet_address]))
    create(index(:notifications, [:game_id]))
  end
end
