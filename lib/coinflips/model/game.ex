defmodule Coinflips.Games.Game do
  use Ecto.Schema
  import Ecto.Changeset

  schema "games" do
    field(:player_wallet, :string)
    field(:challenger_wallet, :string)
    field(:bet_amount, :decimal)
    field(:status, :string)
    field(:creator_deposit_confirmed, :boolean, default: false)
    field(:challenger_deposit_confirmed, :boolean, default: false)
    field(:creator_tx_hash, :string)
    field(:challenger_tx_hash, :string)
    field(:result, :string)

    # Relationship
    has_many(:notifications, Coinflips.Notification)

    timestamps()
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :player_wallet,
      :challenger_wallet,
      :bet_amount,
      :status,
      :creator_deposit_confirmed,
      :challenger_deposit_confirmed,
      :creator_tx_hash,
      :challenger_tx_hash,
      :result
    ])
    |> validate_required([:player_wallet, :bet_amount, :status])
  end
end
