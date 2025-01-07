defmodule Coinflips.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notifications" do
    field(:wallet_address, :string)
    field(:title, :string)
    field(:message, :string)
    field(:unread?, :boolean, default: true)
    belongs_to(:game, Coinflips.Games.Game)

    timestamps()
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:wallet_address, :title, :message, :unread?, :game_id])
    |> validate_required([:wallet_address, :title, :message])
  end
end
