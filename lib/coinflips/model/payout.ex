defmodule Coinflips.Payout do
  @moduledoc """
  The Payout context.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "payouts" do
    field(:tx_hash, :string)
    field(:state, :string, default: "pending")

    belongs_to(:game, YourApp.Games.Game)

    timestamps()
  end

  @doc false
  def changeset(payout, attrs) do
    payout
    |> cast(attrs, [:game_id, :tx_hash, :state])
    |> validate_required([:game_id, :state])
    |> validate_inclusion(:state, ["pending", "completed", "failed"])
  end
end
