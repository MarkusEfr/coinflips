defmodule Coinflips.Payouts do
  @moduledoc """
  The Payouts context.
  """

  alias Coinflips.Repo
  alias Coinflips.Payout

  @doc """
  Creates a payout entry.
  """
  def create_payout(attrs \\ %{}) do
    %Payout{}
    |> Payout.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates the state or transaction hash of a payout.
  """
  def update_payout(payout, attrs) do
    payout
    |> Payout.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Fetches a payout by game ID.
  """
  def get_payout_by_game_id(game_id) do
    Repo.get_by(Payout, game_id: game_id)
  end
end
