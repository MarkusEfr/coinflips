defmodule Coinflips.Games do
  import Ecto.Query, warn: false
  alias Coinflips.Repo
  alias Coinflips.Games.Game

  def transform_params(params) do
    # Ensure `min_bet` and `max_bet` are parsed and converted to Decimal
    min_bet = parse_amount(Map.get(params, "min_bet", nil))
    max_bet = parse_amount(Map.get(params, "max_bet", nil))

    # Ensure `status` is a list of strings
    status =
      params
      |> Map.get("status", [])
      # Ensure it's always a list
      |> List.wrap()
      # Ensure all statuses are strings
      |> Enum.map(&to_string/1)

    # Return the transformed parameters
    %{min_bet: min_bet, max_bet: max_bet, status: status}
  end

  def parse_amount(nil), do: nil
  def parse_amount(""), do: nil
  def parse_amount({value, _}), do: parse_amount(value)

  def parse_amount(amount) when is_binary(amount) do
    case Decimal.parse(amount) do
      {value, _} -> value
      {:ok, value} -> value
      :error -> nil
    end
  end

  def parse_amount(amount) when is_float(amount), do: Decimal.from_float(amount)
  def parse_amount(amount) when is_integer(amount), do: Decimal.new(amount)
  def parse_amount(_), do: nil

  def filter_games(params \\ %{}) do
    # Transform and extract params
    %{min_bet: min_bet, max_bet: max_bet, status: statuses} = transform_params(params)

    # Set default values for bets
    min_bet = min_bet || Decimal.new("0.000")
    max_bet = max_bet || Decimal.new("100.000")

    # Construct the query
    query =
      Game
      |> where([g], g.bet_amount >= ^min_bet)
      |> where([g], g.bet_amount <= ^max_bet)
      |> status_filter(statuses)
      |> order_by([g], desc: g.inserted_at)

    Repo.all(query)
  end

  # Helper function to map statuses to categories
  defp status_filter(query, statuses) do
    query
    |> where(
      [g],
      fragment(
        """
        (
          CASE
            WHEN ? LIKE '🏆%' AND result IN ('Heads', 'Tails') THEN 'completed'
            WHEN ? = '⚔️ Ready to Flip' AND result = 'pending' THEN 'ready'
            WHEN ? = '🎯 Waiting for challenger' AND result = 'pending' THEN 'waiting'
            ELSE NULL
          END
        ) = ANY(?)
        """,
        g.status,
        g.status,
        g.status,
        ^statuses
      )
    )
  end

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
