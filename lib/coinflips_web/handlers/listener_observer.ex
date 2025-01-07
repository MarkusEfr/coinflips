defmodule CoinflipsWeb.Handlers.ListenerObserver do
  @moduledoc """
  This module contains handlers for the Listener
  """

  use CoinflipsWeb, :live_component

  alias Coinflips.Notifications

  # Remove a tip  @impl true
  def handle_info({:remove_tip, tip_id}, socket) do
    updated_tips = Enum.reject(socket.assigns.tip_list, fn tip -> tip.id == tip_id end)
    {:noreply, assign(socket, tip_list: updated_tips)}
  end

  def handle_info({:hide_tip, tip_id}, socket) do
    {:noreply,
     assign(socket,
       tip_list: Enum.reject(socket.assigns.tip_list, fn tip -> tip.id == tip_id end)
     )}
  end

  def handle_info(
        %{event: "update_notifications", payload: %{wallet_address: wallet_address}},
        socket
      )
      when is_binary(wallet_address) and wallet_address == socket.assigns.wallet_address do
    notifications = Notifications.get_notifications_by_wallet(wallet_address)

    grouped_notifications =
      case socket.assigns.group_by do
        "unread?" -> Notifications.group_notifications_by_status(notifications)
        "date" -> Notifications.group_notifications_by_date(notifications)
        _ -> Notifications.group_notifications_by_status(notifications)
      end

    {:noreply,
     assign(socket, notifications: notifications, grouped_notifications: grouped_notifications)}
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

  def handle_info({:release_lock, id}, socket) do
    locked_games = Map.get(socket.assigns, :locked_games, %{})
    {:noreply, assign(socket, :locked_games, Map.delete(locked_games, id))}
  end

  # Lock a game
  def handle_info(%{event: "lock_game", payload: %{game_id: game_id}}, socket) do
    locked_games = Map.get(socket.assigns, :locked_games, %{})

    if Map.get(locked_games, game_id) do
      # Already locked, no change
      {:noreply, socket}
    else
      {:noreply, assign(socket, :locked_games, Map.put(locked_games, game_id, true))}
    end
  end

  # Unlock a game
  def handle_info(%{event: "unlock_game", payload: %{game_id: game_id}}, socket) do
    locked_games = Map.get(socket.assigns, :locked_games, %{})
    {:noreply, assign(socket, :locked_games, Map.delete(locked_games, game_id))}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp paginate_games(games, page, per_page),
    do: Enum.chunk_every(games, per_page) |> Enum.at(page - 1, [])
end
