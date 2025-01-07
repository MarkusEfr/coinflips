defmodule CoinflipsWeb.Handlers.EventCommandor do
  @moduledoc """
  This module contains handlers for the Events
  """

  use CoinflipsWeb, :live_component

  import CoinflipsWeb.Endpoint, only: [broadcast: 3]
  alias Coinflips.{Notifications, Games}

  @min_bet 0.001
  @topic "games"
  @notify_topic "notifications"
  @app_wallet_address "0xa1207Ea48191889e931e11415cE13DF5d9654852"

  def handle_event("select_section", %{"section" => section}, socket) do
    {:noreply, assign(socket, selected_section: section)}
  end

  @impl true
  def handle_event("change_page", %{"page" => page}, socket) do
    page = String.to_integer(page)
    games_per_page = socket.assigns.games_per_page

    # Get paginated games for the selected page
    paginated_games = paginate_games(socket.assigns.active_games, page, games_per_page)

    {:noreply,
     assign(socket,
       current_page: page,
       paginated_games: paginated_games
     )}
  end

  @impl true
  def handle_event("filter_games", params, socket) do
    filtered_games = Games.filter_games(params)

    {:noreply,
     assign(socket,
       active_games: filtered_games,
       paginated_games: filtered_games |> paginate_games(1, socket.assigns.games_per_page),
       total_pages: calculate_total_pages(filtered_games, socket.assigns.games_per_page),
       current_page: 1,
       filter_min_bet: Map.get(params, "min_bet", nil),
       filter_max_bet: Map.get(params, "max_bet", nil),
       filter_status: Map.get(params, "status", [])
     )}
  end

  # Bet Validation
  def handle_event("validate_bet", %{"bet_amount" => bet_amount, "balance" => balance}, socket) do
    bet_amount = bet_amount |> Games.parse_amount()

    tip =
      cond do
        bet_amount == 0.000 -> "⚠️ Enter a valid bet amount."
        bet_amount < @min_bet -> "💡 Bet must be at least #{@min_bet} ETH."
        bet_amount > balance -> "💸 Not enough ETH balance."
        true -> nil
      end

    socket =
      if tip, do: add_tip(socket, tip), else: socket

    {:noreply, assign(socket, bet_amount: bet_amount)}
  end

  def handle_event("start_coin_flip", _params, socket) do
    {:noreply, push_event(socket, "coin-flip", %{})}
  end

  @impl true
  def handle_event("group_by", %{"group_by" => group_by}, socket) do
    grouped_history = Games.group_game_history(socket.assigns.game_history, group_by)
    {:noreply, assign(socket, grouped_history: grouped_history, group_by: group_by)}
  end

  # Wallet Connection
  @impl true
  def handle_event("wallet_connected", %{"address" => address, "balance" => balance}, socket) do
    game_history = Games.get_user_game_history(address)
    balance = String.to_float(balance)
    grouped_history = Games.group_game_history(game_history, "day")
    message = "Ready to play"

    {:ok, notification} =
      Notifications.create_notification(%{
        wallet_address: address,
        title: "🔗 Wallet connected!",
        message: message
      })

    notification |> IO.inspect(label: "notifications")

    broadcast(@notify_topic, "update_notifications", %{
      notification: notification,
      wallet_address: address
    })

    {:noreply,
     add_tip(socket, message)
     |> assign(
       wallet_connected: true,
       wallet_address: address,
       wallet_balance: balance,
       game_history: game_history,
       grouped_history: grouped_history
     )}
  end

  def handle_event("create_game", %{"bet_amount" => bet_amount, "balance" => balance}, socket) do
    cond do
      bet_amount < @min_bet ->
        {:noreply, add_tip(socket, "⚠️ Minimum bet is #{@min_bet} ETH.")}

      bet_amount > balance ->
        {:noreply, add_tip(socket, "💸 Insufficient balance to create the game.")}

      true ->
        {:ok, new_game} =
          Coinflips.Games.create_game(%{
            player_wallet: socket.assigns.wallet_address,
            bet_amount: bet_amount,
            status: "🎯 Waiting for challenger"
          })

        event_params = %{
          toAddress: app_wallet_address(),
          amountInEth: bet_amount,
          game_id: new_game.id,
          role: "creator"
        }

        {:noreply,
         socket
         |> assign(bet_amount: nil)
         |> add_tip("🎯 Deposit ETH to start the game!")
         |> push_event("deposit_eth", event_params)}
    end
  end

  def handle_event("join_game", %{"id" => id, "balance" => balance}, socket) do
    locked_games = Map.get(socket.assigns, :locked_games, %{})

    if Map.get(locked_games, id) do
      {:noreply, add_tip(socket, "⚠️ This game is currently being processed.")}
    else
      # Lock the game
      CoinflipsWeb.Endpoint.broadcast("games", "lock_game", %{game_id: id})

      game = Coinflips.Games.get_game!(id)

      if Decimal.new(balance) < Decimal.new(game.bet_amount) do
        # Unlock the game on failure
        CoinflipsWeb.Endpoint.broadcast("games", "unlock_game", %{game_id: id})
        {:noreply, add_tip(socket, "💸 Insufficient balance to join the game.")}
      else
        join_params = %{
          toAddress: app_wallet_address(),
          amountInEth: game.bet_amount |> Decimal.to_string(),
          game_id: id,
          role: "challenger"
        }

        {:noreply,
         socket
         |> add_tip("💰 Deposit ETH to join the game.")
         |> push_event("deposit_eth", join_params)}
      end
    end
  end

  def handle_event(
        "eth_deposit_success",
        %{
          "bet_amount" => bet_amount,
          "game_id" => game_id,
          "role" => role,
          "txHash" => tx_hash,
          "wallet_address" => wallet_address
        },
        socket
      ) do
    # Find the game by ID from the database
    game = Coinflips.Games.get_game!(game_id)

    if game do
      updated_attrs =
        case role do
          "creator" ->
            %{
              creator_deposit_confirmed: true,
              creator_tx_hash: tx_hash,
              status: status_by_challenger_deposit(game, :creator),
              result: "pending"
            }

          "challenger" ->
            %{
              challenger_wallet: wallet_address,
              challenger_deposit_confirmed: true,
              challenger_tx_hash: tx_hash,
              status: status_by_challenger_deposit(game, :challenger)
            }
        end

      # Update the game in the database
      {:ok, updated_game} = Coinflips.Games.update_game(game, updated_attrs)

      # Broadcast the single updated game
      broadcast(
        @topic,
        "update_games",
        {:update_game, updated_game, is_new?: false}
      )

      # Unlock the game after successful deposit
      CoinflipsWeb.Endpoint.broadcast("games", "unlock_game", %{game_id: game_id})
      # Add a tip
      {:noreply, socket |> add_tip("💰 Deposit confirmed for game #{game_id}.")}
    else
      # Handle the case where the game does not exist; create a new game
      new_game_attrs = %{
        id: game_id,
        bet_amount: bet_amount,
        player_wallet: if(role == "creator", do: socket.assigns.wallet_address, else: nil),
        challenger_wallet: if(role == "challenger", do: socket.assigns.wallet_address, else: nil),
        creator_deposit_confirmed: role == "creator",
        challenger_deposit_confirmed: role == "challenger",
        creator_tx_hash: if(role == "creator", do: tx_hash, else: nil),
        challenger_tx_hash: if(role == "challenger", do: tx_hash, else: nil),
        status: if(role == "creator", do: "🎯 Waiting for challenger", else: "⚔️ Ready to Flip")
      }

      {:ok, new_game} = Coinflips.Games.create_game(new_game_attrs)

      # Broadcast the new game
      broadcast(
        @topic,
        "update_games",
        {:update_game, new_game, is_new?: true}
      )

      # Unlock the game after successful deposit
      CoinflipsWeb.Endpoint.broadcast("games", "unlock_game", %{game_id: game_id})
      # Add a tip
      {:noreply, socket |> add_tip("💰 Deposit confirmed for game #{game_id}.")}
    end
  end

  def handle_event(
        "eth_deposit_failure",
        %{"error" => %{"shortMessage" => short_message}, "game_id" => game_id, "role" => role},
        socket
      ) do
    CoinflipsWeb.Endpoint.broadcast("games", "unlock_game", %{game_id: game_id})

    case role do
      "creator" ->
        Coinflips.Games.update_game(Coinflips.Games.get_game!(game_id), %{
          status: "❌ Game failed #{short_message}",
          result: "⚠️ Creator deposit failed for game #{game_id}: #{short_message}."
        })

        {:noreply,
         add_tip(socket, "⚠️ Creator deposit failed for game #{game_id}: #{short_message}.")}

      "challenger" ->
        {:noreply,
         add_tip(socket, "⚠️ Challenger deposit failed for game #{game_id}: #{short_message}.")}
    end
  end

  def handle_event("trigger_coin_flip", %{"id" => game_id}, socket) do
    flip_result = Enum.random(["Heads", "Tails"])
    game = Coinflips.Games.get_game!(game_id)

    winner_wallet =
      if flip_result == "Heads", do: game.player_wallet, else: game.challenger_wallet

    # Broadcast the animation separately
    {:noreply,
     socket
     |> push_event("animate_coin_flip", %{
       game_id: game_id,
       result: flip_result,
       winner_address: winner_wallet
     })}
  end

  def handle_event("finalize_flip_result", %{"id" => game_id, "result" => result}, socket) do
    game = Coinflips.Games.get_game!(game_id)
    winner_wallet = if result == "Heads", do: game.player_wallet, else: game.challenger_wallet

    updated_attrs = %{
      status: "🏆 #{winner_wallet} wins!",
      result: result,
      winner_wallet: winner_wallet
    }

    # {:ok, updated_game} = Coinflips.Games.update_game(game, updated_attrs)

    # Define threshold percentage (e.g., 5%)
    threshold_percentage = 5

    # broadcast(@topic, "update_games", {:update_game, updated_game})

    {
      :noreply,
      socket
      |> add_tip("
    🏆 #{result}! #{winner_wallet} wins with #{game.bet_amount} ETH.")
      #  |> push_event("send_payout", %{
      #    "winner" => winner_wallet,
      #    "amount" => game.bet_amount |> Decimal.mult(2),
      #    "game_id" => game_id,
      #    "payout_sys" => %{
      #      key: System.get_env("APP_PRIVATE_KEY") |> String.trim(),
      #      provider_url: System.get_env("PROVIDER_URL") |> String.trim()
      #    },
      #    "threshold" => threshold_percentage
      #  })
    }
  end

  def handle_event("payout_success", %{"game_id" => game_id, "txHash" => tx_hash}, socket) do
    IO.puts("✅ Payout successful! TX Hash: #{tx_hash}")

    case Payouts.get_payout_by_game_id(game_id) do
      nil ->
        # Create a new payout record if it doesn't exist
        case Payouts.create_payout(%{
               game_id: game_id,
               tx_hash: tx_hash,
               state: "completed"
             }) do
          {:ok, _new_payout} ->
            {:noreply, add_tip(socket, "🏆 Payout created and sent! Transaction: #{tx_hash}")}

          {:error, changeset} ->
            IO.puts("⚠️ Failed to create payout record: #{inspect(changeset.errors)}")
            {:noreply, add_tip(socket, "⚠️ Payout sent, but failed to create record.")}
        end

      payout ->
        # Update the existing payout record
        case Payouts.update_payout(payout, %{tx_hash: tx_hash, state: "completed"}) do
          {:ok, _updated_payout} ->
            {:noreply, add_tip(socket, "🏆 Payout updated and sent! Transaction: #{tx_hash}")}

          {:error, changeset} ->
            IO.puts("⚠️ Failed to update payout record: #{inspect(changeset.errors)}")
            {:noreply, add_tip(socket, "⚠️ Payout sent, but failed to update record.")}
        end
    end
  end

  def handle_event("payout_failure", %{"game_id" => game_id, "error" => error}, socket) do
    IO.puts("❌ Payout failed: #{error}")

    case Payouts.get_payout_by_game_id(game_id) do
      nil ->
        # Create a new payout record if it doesn't exist
        case Payouts.create_payout(%{game_id: game_id, state: "failed"}) do
          {:ok, _new_payout} ->
            {:noreply, add_tip(socket, "⚠️ Payout failure recorded: #{error}")}

          {:error, changeset} ->
            IO.puts("⚠️ Failed to create payout record: #{inspect(changeset.errors)}")
            {:noreply, add_tip(socket, "⚠️ Failed to create payout record for game #{game_id}.")}
        end

      payout ->
        # Update the existing payout record
        case Payouts.update_payout(payout, %{state: "failed"}) do
          {:ok, _updated_payout} ->
            {:noreply, add_tip(socket, "⚠️ Payout failure recorded: #{error}")}

          {:error, changeset} ->
            IO.puts("⚠️ Failed to update payout record: #{inspect(changeset.errors)}")
            {:noreply, add_tip(socket, "⚠️ Failed to update payout record for game #{game_id}.")}
        end
    end
  end

  def handle_event("payout_delayed", %{"game_id" => game_id, "winner" => winner}, socket) do
    IO.puts("⏳ Payment for Game #{game_id} delayed due to high gas fees. Winner: #{winner}")

    case Payouts.get_payout_by_game_id(game_id) do
      nil ->
        # Create a new payout record if it doesn't exist
        case Payouts.create_payout(%{game_id: game_id, state: "delayed"}) do
          {:ok, _new_payout} ->
            {:noreply, add_tip(socket, "⏳ Payment delayed due to high gas fees.")}

          {:error, changeset} ->
            IO.puts("⚠️ Failed to create payout record: #{inspect(changeset.errors)}")
            {:noreply, add_tip(socket, "⚠️ Failed to create payout record for game #{game_id}.")}
        end

      payout ->
        # Update the existing payout record
        case Payouts.update_payout(payout, %{state: "delayed"}) do
          {:ok, _updated_payout} ->
            {:noreply, add_tip(socket, "⏳ Payment delayed due to high gas fees.")}

          {:error, changeset} ->
            IO.puts("⚠️ Failed to update payout record: #{inspect(changeset.errors)}")
            {:noreply, add_tip(socket, "⚠️ Failed to update payout record for game #{game_id}.")}
        end
    end
  end

  @impl true
  def handle_event("group_notifications", %{"group_by" => group_by}, socket) do
    grouped_notifications =
      case group_by do
        "unread?" -> Notifications.group_notifications_by_status(socket.assigns.notifications)
        "date" -> Notifications.group_notifications_by_date(socket.assigns.notifications)
      end

    {:noreply, assign(socket, grouped_notifications: grouped_notifications, group_by: group_by)}
  end

  @impl true
  def handle_event("toggle_notifications", _, socket) do
    {:noreply, assign(socket, show_notifications: !socket.assigns.show_notifications)}
  end

  @impl true
  def handle_event("close_notifications", _, socket) do
    {:noreply, assign(socket, show_notifications: false)}
  end

  @impl true
  def handle_event("filter_games", params, socket) do
    filtered_games = Games.filter_games(params)

    {:noreply,
     assign(socket,
       active_games: filtered_games,
       paginated_games: filtered_games |> paginate_games(1, socket.assigns.games_per_page),
       total_pages: calculate_total_pages(filtered_games, socket.assigns.games_per_page),
       current_page: 1,
       filter_min_bet: Map.get(params, "min_bet", nil),
       filter_max_bet: Map.get(params, "max_bet", nil),
       filter_status: Map.get(params, "status", [])
     )}
  end

  def handle_event("mark_as_read", %{"id" => id}, socket) do
    with {:ok, _} <- Coinflips.Notifications.mark_as_read(id) do
      broadcast(
        @notify_topic,
        "update_notifications",
        %{
          wallet_address: socket.assigns.wallet_address,
          notifications: []
        }
      )
    end

    {:noreply, socket}
  end

  # Additional event handlers can be added here
  defp calculate_total_pages(games, games_per_page),
    do: max(div(length(games) + games_per_page - 1, games_per_page), 1)

  defp paginate_games(games, page, games_per_page),
    do: Enum.chunk_every(games, games_per_page) |> Enum.at(page - 1, [])

  defp add_tip(socket, message) do
    tip_id = :erlang.system_time(:millisecond)

    # Add tip to the tip list
    updated_tips = [%{id: tip_id, message: message} | socket.assigns.tip_list]

    # Auto-remove the tip after a delay without affecting other processes
    Process.send_after(self(), {:hide_tip, tip_id}, 1750)

    assign(socket, tip_list: updated_tips)
  end

  defp app_wallet_address(), do: @app_wallet_address

  defp status_by_challenger_deposit(%{creator_deposit_confirmed: true}, :challenger),
    do: "⚔️ Ready to Flip"

  defp status_by_challenger_deposit(_, :creator), do: "🎯 Waiting for challenger"
end
