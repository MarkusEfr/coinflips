defmodule CoinflipsWeb.Handlers.ListenerObserver do
  @moduledoc """
  This module contains handlers for the Listener
  """

  use CoinflipsWeb, :live_component

  # Remove a tip  @impl true
  def handle_info({:remove_tip, tip_id}, socket) do
    updated_tips = Enum.reject(socket.assigns.tip_list, fn tip -> tip.id == tip_id end)
    {:noreply, assign(socket, tip_list: updated_tips)}
  end

  # Clear Tip Message after Timeout
  def handle_info(:clear_tip, tip_id, socket) do
    # Auto-hide after 3 seconds
    Process.send_after(self(), :hide_tip, 5000)
    {:noreply, socket}
  end

  def handle_info({:hide_tip, tip_id}, socket) do
    {:noreply,
     assign(socket,
       tip_list: Enum.reject(socket.assigns.tip_list, fn tip -> tip.id == tip_id end)
     )}
  end

  # PubSub Event Handlers
  def handle_info(
        %{event: "update_games", payload: {:update_game, new_game, is_new?: is_new?}},
        %{assigns: %{active_games: active_games}} = socket
      ) do
    active_games =
      if is_new? do
        # Add new game to the beginning of the list
        [new_game | active_games]
      else
        # Update the existing game in the list
        Enum.map(active_games, fn game ->
          if game.id == new_game.id, do: new_game, else: game
        end)
      end

    {:noreply,
     assign(socket,
       active_games: active_games,
       paginated_games:
         paginate_games(active_games, socket.assigns.current_page, socket.assigns.games_per_page)
     )}
  end

  defp paginate_games(games, page, per_page),
    do: Enum.chunk_every(games, per_page) |> Enum.at(page - 1, [])
end
