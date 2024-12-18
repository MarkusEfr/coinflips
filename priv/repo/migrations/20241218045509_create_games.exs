defmodule Coinflips.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games) do
      add :player_wallet, :string
      add :challenger_wallet, :string
      add :bet_amount, :decimal
      add :status, :string
      add :creator_deposit_confirmed, :boolean, default: false, null: false
      add :challenger_deposit_confirmed, :boolean, default: false, null: false
      add :creator_tx_hash, :string
      add :challenger_tx_hash, :string
      add :result, :string

      timestamps(type: :utc_datetime)
    end
  end
end
