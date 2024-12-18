defmodule CoinflipsWeb.Live.Index do
  use CoinflipsWeb, :live_view

  @topic "games"
  @min_bet 0.001
  @app_wallet_address "0xa1207Ea48191889e931e11415cE13DF5d9654852"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: CoinflipsWeb.Endpoint.subscribe(@topic)

    {:ok,
     assign(socket,
       wallet_connected: false,
       wallet_address: nil,
       wallet_balance: 0.0,
       active_games: Coinflips.Games.list_games(),
       bet_amount: nil,
       tip_list: []
     )}
  end

  # Remove a tip
  @impl true
  def handle_info({:remove_tip, tip_id}, socket) do
    updated_tips = Enum.reject(socket.assigns.tip_list, fn tip -> tip.id == tip_id end)
    {:noreply, assign(socket, tip_list: updated_tips)}
  end

  # Clear Tip Message after Timeout
  @impl true
  def handle_info(:clear_tip, socket) do
    # Auto-hide after 3 seconds
    Process.send_after(self(), :hide_tip, 5000)
    {:noreply, socket}
  end

  def handle_info(:hide_tip, socket) do
    {:noreply, assign(socket, tip_list: [])}
  end

  # PubSub Event Handlers
  @impl true
  def handle_info(%{event: "update_games", payload: {:update_game, _new_game}}, socket) do
    {:noreply, assign(socket, active_games: Coinflips.Games.list_games())}
  end

  # Wallet Connection
  @impl true
  def handle_event("wallet_connected", %{"address" => address, "balance" => balance}, socket) do
    balance = String.to_float(balance)

    {:noreply,
     add_tip(socket, "🔗 Wallet connected! Ready to play.")
     |> assign(wallet_connected: true, wallet_address: address, wallet_balance: balance)}
  end

  # Bet Validation
  def handle_event("validate_bet", %{"bet_amount" => bet_amount}, socket) do
    bet_amount = bet_amount |> parse_amount()

    tip =
      cond do
        bet_amount == 0.000 -> "⚠️ Enter a valid bet amount."
        bet_amount < @min_bet -> "💡 Bet must be at least #{@min_bet} ETH."
        bet_amount > socket.assigns.wallet_balance -> "💸 Not enough ETH balance."
        true -> nil
      end

    socket =
      if tip, do: add_tip(socket, tip), else: socket

    {:noreply, assign(socket, bet_amount: bet_amount)}
  end

  def handle_event("create_game", _params, socket) do
    bet_amount = socket.assigns.bet_amount

    cond do
      bet_amount < @min_bet ->
        {:noreply, add_tip(socket, "⚠️ Minimum bet is #{@min_bet} ETH.")}

      bet_amount > socket.assigns.wallet_balance ->
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

        CoinflipsWeb.Endpoint.broadcast(@topic, "update_games", {:update_game, new_game})

        {:noreply,
         socket
         |> assign(bet_amount: nil)
         |> add_tip("🎯 Deposit ETH to start the game!")
         |> push_event("deposit_eth", event_params)}
    end
  end

  def handle_event("join_game", %{"id" => id, "balance" => balance}, socket) do
    %{bet_amount: bet_amount} = game = Coinflips.Games.get_game!(id)

    IO.inspect(game, label: "game")
    IO.inspect(balance |> Decimal.new(), label: "balance")

    join_params = %{
      toAddress: app_wallet_address(),
      amountInEth: bet_amount |> Decimal.to_string(),
      game_id: id,
      role: "challenger"
    }

    if balance |> Decimal.new() >= bet_amount do
      {:noreply,
       socket
       |> add_tip("💰 Deposit ETH to join the game.")
       |> push_event("deposit_eth", join_params)}
    else
      {:noreply, add_tip(socket, "💸 Insufficient balance to join the game.")}
    end
  end

  def handle_event("flip_coin", %{"id" => id, "wallet" => wallet}, socket) do
    # Fetch the game from the database
    game = Coinflips.Games.get_game!(id)

    if game.status == "⚔️ Ready to Flip" do
      # Simulate the coin flip
      flip_result = Enum.random(["Heads", "Tails"])

      # Determine the winner based on the flip result
      winner_wallet =
        cond do
          flip_result == "Heads" -> game.player_wallet
          flip_result == "Tails" -> game.challenger_wallet
        end

      # Update the game status and winner in the database
      updated_attrs = %{
        status: "🏆 #{winner_wallet} wins!",
        flip_result: flip_result,
        winner_wallet: winner_wallet
      }

      {:ok, updated_game} = Coinflips.Games.update_game(game, updated_attrs)

      # Broadcast the updated game
      CoinflipsWeb.Endpoint.broadcast(@topic, "update_games", {:update_game, updated_game})

      # Send a tip to notify about the flip result
      {:noreply, socket |> add_tip("🎲 Coin flipped! #{flip_result} wins!")}
    else
      {:noreply, add_tip(socket, "⚠️ Game is not ready for flipping!")}
    end
  end

  def handle_event(
        "eth_deposit_success",
        %{"txHash" => tx_hash, "game_id" => game_id, "bet_amount" => bet_amount, "role" => role},
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
              status: status_by_challenger_deposit(game)
            }

          "challenger" ->
            %{
              challenger_deposit_confirmed: true,
              challenger_tx_hash: tx_hash,
              status: status_by_challenger_deposit(game)
            }
        end

      # Update the game in the database
      {:ok, updated_game} = Coinflips.Games.update_game(game, updated_attrs)

      # Broadcast the single updated game
      CoinflipsWeb.Endpoint.broadcast(@topic, "update_games", {:update_game, updated_game})

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
      CoinflipsWeb.Endpoint.broadcast(@topic, "update_games", {:update_game, new_game})

      {:noreply, socket |> add_tip("💰 Deposit confirmed for game #{game_id}.")}
    end
  end

  def handle_event(
        "eth_deposit_failure",
        %{"error" => error, "game_id" => game_id, "role" => role},
        socket
      ) do
    message =
      case role do
        "creator" -> "⚠️ Creator deposit failed for game #{game_id}: #{error}."
        "challenger" -> "⚠️ Challenger deposit failed for game #{game_id}: #{error}."
      end

    Coinflips.Games.update_game(Coinflips.Games.get_game!(game_id), %{
      status: "❌ Game failed "
    })

    {:noreply, add_tip(socket, message)}
  end

  defp add_tip(socket, message) do
    tip_id = :erlang.system_time(:millisecond)

    # Add tip to list
    updated_tips = [%{id: tip_id, message: message} | socket.assigns.tip_list]
    # Auto-remove after 3 seconds
    Process.send_after(self(), {:remove_tip, tip_id}, 3000)

    assign(socket, tip_list: updated_tips)
  end

  defp parse_amount(nil), do: 0.0

  defp parse_amount(amount) when is_binary(amount) do
    case Float.parse(amount) do
      {value, ""} -> value
      _ -> 0.0
    end
  end

  defp parse_amount(amount) when is_float(amount), do: amount
  defp parse_amount(_), do: 0.0

  defp min_bet(), do: @min_bet

  defp app_wallet_address(), do: @app_wallet_address

  # Render
  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-gray-950 text-white font-mono">
      <div class="absolute top-4 right-4 space-y-2 z-50">
        <div
          :for={tip <- @tip_list}
          class="bg-gray-800 text-neon-green shadow-lg rounded-lg px-4 py-2 animate-slide-in transition-opacity duration-300"
        >
          {tip.message}
        </div>
      </div>
      <!-- Hero Section -->
      <div class="p-6 md:p-10 text-center bg-gradient-to-b from-gray-800 to-black">
        <h1 class="text-3xl md:text-5xl font-extrabold text-neon-purple animate-pulse mb-4">
          ⚡ COINFLIP BATTLE ⚡
        </h1>
        <p class="text-gray-400 text-lg md:text-xl">Flip the coin. Feel the thrill. Win ETH! 🚀</p>

        <button
          :if={!@wallet_connected}
          id="wallet-connect"
          phx-hook="WalletConnect"
          class="mt-6 bg-neon-blue hover:bg-neon-green px-6 py-2 rounded-full font-bold shadow-lg hover:scale-110 transition"
        >
          🔗 Connect Wallet
        </button>
      </div>
      
    <!-- Wallet Section -->
      <div
        :if={@wallet_connected}
        class="w-full max-w-lg mx-auto mt-6 p-4 bg-gray-900 rounded-lg shadow-lg"
      >
        <h2 class="text-xl font-bold text-neon-green mb-4 text-center">👛 Wallet Overview</h2>
        <div class="grid gap-4 text-sm text-gray-300">
          <div class="flex items-center justify-between bg-gray-800 p-3 rounded-lg">
            <span class="text-neon-blue">🔑 Address</span>
            <p class="truncate bg-gray-700 px-2 py-1 rounded font-mono w-4/5">{@wallet_address}</p>
          </div>
          <div class="flex items-center justify-between bg-gray-800 p-3 rounded-lg">
            <span class="text-neon-purple">💰 Balance</span>
            <p class="text-neon-green font-bold">{@wallet_balance} ETH</p>
          </div>
        </div>
      </div>
      
    <!-- Game Creation -->
      <div
        id="create-game"
        class="w-full max-w-lg mx-auto mt-6 p-6 bg-gray-800 rounded-lg shadow-lg"
        phx-hook="GameActions"
      >
        <h2 class="text-2xl text-center font-bold text-neon-blue mb-4">🎯 Start a Game</h2>
        <form phx-change="validate_bet" phx-submit="create_game" class="flex flex-col gap-4">
          <input
            type="number"
            step="0.001"
            min={min_bet()}
            name="bet_amount"
            placeholder={"Enter bet (Min: #{min_bet()} ETH)"}
            class="w-full p-3 rounded-lg bg-gray-700 text-white placeholder-gray-400 focus:ring focus:ring-neon-green"
          />
          <button
            disabled={is_nil(@wallet_connected) || is_nil(@bet_amount)}
            type="submit"
            class="w-full p-3 rounded-full bg-neon-green hover:bg-neon-blue text-black font-bold hover:scale-105 transition"
          >
            🚀 Create Game
          </button>
        </form>
      </div>
      
    <!-- Active Games -->
      <div class="w-full mt-6 px-6 overflow-x-auto no-scrollbar">
        <h2 class="text-center text-2xl font-bold text-neon-purple mb-4">🔥 Active Games</h2>
        <div class="flex gap-4">
          <div
            :for={game <- @active_games}
            :if={game.creator_deposit_confirmed}
            class="min-w-[250px] bg-gray-700 p-4 rounded-lg shadow-lg hover:scale-105 transition"
          >
            <p class="text-neon-green font-bold truncate">🎭 Player: {game.player_wallet}</p>
            <p class="text-neon-blue font-bold">💰 Bet: {game.bet_amount} ETH</p>
            <p class="text-gray-400 text-sm">{game.status}</p>
            <button
              :if={game.status == "🎯 Waiting for challenger" and @wallet_connected}
              phx-click="join_game"
              phx-value-id={game.id}
              phx-value-balance={@wallet_balance}
              class="w-full mt-3 p-2 rounded-lg bg-neon-purple hover:bg-neon-green text-black font-bold transition"
            >
              ⚔️ Join Game
            </button>
            <!-- Flip Coin -->
            <button
              :if={
                @wallet_connected &&
                  game.status == "⚔️ Ready to Flip" &&
                  @wallet_address in [game.player_wallet, game.challenger_wallet]
              }
              phx-click="flip_coin"
              phx-value-id={game.id}
              phx-value-wallet={@wallet_address}
              class="w-full mt-3 p-2 rounded-lg bg-neon-blue hover:bg-neon-green text-black font-bold transition"
            >
              🎲 Flip Coin
            </button>
          </div>
        </div>
      </div>
      
    <!-- Footer -->
      <footer class="mt-auto p-4 bg-gray-900 text-center text-gray-400">
        <div class="flex justify-center gap-2">
          <p>🚀 Powered by <span class="text-neon-purple font-bold">ETH</span></p>
          <span>✨ Play Smart. Win Big! 🎲</span>
        </div>
      </footer>
    </div>
    """
  end

  defp status_by_challenger_deposit(%{challenger_deposit_confirmed: true} = _game),
    do: "⚔️ Ready to Flip"

  defp status_by_challenger_deposit(_game), do: "🎯 Waiting for challenger"
end
