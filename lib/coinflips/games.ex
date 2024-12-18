defmodule Coinflips.Games do
  import Ecto.Query, warn: false
  alias Coinflips.Repo
  alias Coinflips.Games.Game

  def list_games do
    Game
    |> where([g], g.result in [nil, "pending"])
    |> order_by([g], desc: g.inserted_at)
    |> Repo.all()
  end

  def get_game!(id) do
    Repo.get!(Game, id)
  end

  def create_game(attrs \\ %{}) do
    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  def update_game(%Game{} = game, attrs) do
    game
    |> Game.changeset(attrs)
    |> Repo.update()
  end

  def delete_game(%Game{} = game) do
    Repo.delete(game)
  end
end
