defmodule CoinflipsWeb.Live.Index do
  use CoinflipsWeb, :live_view

  @topic "games"
  @min_bet 0.001
  @app_wallet_address "0xa1207Ea48191889e931e11415cE13DF5d9654852"

  @provider_url System.get_env("PROVIDER_URL")
  @private_key System.get_env("APP_PRIVATE_KEY")

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

  def handle_event("start_coin_flip", _params, socket) do
    {:noreply, push_event(socket, "coin-flip", %{})}
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
    %{bet_amount: bet_amount} = _game = Coinflips.Games.get_game!(id)

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

  def handle_event("flip_coin", %{"id" => id}, socket) do
    game = Coinflips.Games.get_game!(id)

    if game.status == "⚔️ Ready to Flip" do
      flip_result = Enum.random(["Heads", "Tails"])

      winner_wallet =
        if flip_result == "Heads", do: game.player_wallet, else: game.challenger_wallet

      updated_attrs = %{
        status: "🏆 #{winner_wallet} wins!",
        result: flip_result,
        winner_wallet: winner_wallet
      }

      {:ok, updated_game} = Coinflips.Games.update_game(game, updated_attrs)

      # Broadcast updated game and push payout event to the client
      CoinflipsWeb.Endpoint.broadcast(@topic, "update_games", {:update_game, updated_game})

      {:noreply,
       socket
       |> add_tip("🎲 Coin flipped! #{flip_result} wins!")
       |> push_event("send_payout", %{winner: winner_wallet, amount: game.bet_amount})}
    else
      {:noreply, add_tip(socket, "⚠️ Game is not ready for flipping!")}
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
              status: status_by_challenger_deposit(game, :challenger),
              result: "pending"
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
        %{"error" => %{"shortMessage" => short_message}, "game_id" => game_id, "role" => role},
        socket
      ) do
    message =
      case role do
        "creator" -> "⚠️ Creator deposit failed for game #{game_id}: #{short_message}."
        "challenger" -> "⚠️ Challenger deposit failed for game #{game_id}: #{short_message}."
      end

    Coinflips.Games.update_game(Coinflips.Games.get_game!(game_id), %{
      status: "❌ Game failed #{short_message}",
      result: "failed"
    })

    {:noreply, add_tip(socket, message)}
  end

  def handle_event("payout_success", %{"txHash" => tx_hash}, socket) do
    IO.puts("✅ Payout successful! TX Hash: #{tx_hash}")
    {:noreply, add_tip(socket, "🏆 Payout sent! Transaction: #{tx_hash}")}
  end

  def handle_event("payout_failure", %{"error" => error}, socket) do
    IO.puts("❌ Payout failed: #{error}")
    {:noreply, add_tip(socket, "⚠️ Payout failed: #{error}")}
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
    <div id="payout-hook" phx-hook="PayoutHook"></div>

      <div id="coin-container" class="fixed inset-0 z-50 pointer-events-none">
        <div
          id="coin"
          class="absolute hidden w-16 h-16 bg-yellow-500 rounded-full shadow-lg transform scale-150"
          style="right: 25%; top: 0;"
        >
        </div>
        <div
          id="coin-result"
          class="absolute hidden text-4xl font-bold text-white text-center w-full"
          style="top: 50%; transform: translateY(-50%);"
        >
        </div>
      </div>

    <!-- Notifications Section -->
      <div class="absolute top-4 right-4 space-y-2 z-50">
        <div
          :for={tip <- @tip_list}
          class="bg-gray-800 text-neon-green shadow-lg rounded-lg px-4 py-2 animate-slide-in transition-opacity duration-300"
        >
          {tip.message}
        </div>
      </div>

    <!-- Main Content -->
      <div class="flex-grow flex flex-col">
        <!-- Hero Section -->
        <div class="p-6 md:p-10 text-center bg-gradient-to-b from-gray-800 to-black">
          <h1 class="text-3xl md:text-5xl font-extrabold text-neon-purple animate-pulse mb-4">
            ⚡ COINFLIP BATTLE ⚡
          </h1>
          <p class="text-gray-400 text-lg md:text-xl">Flip the coin. Feel the thrill. Win ETH! 🚀</p>
          <button
            id="flip-coin-trigger"
            onclick="triggerCoinFlip()"
            class="absolute top-6 right-1/3 transform translate-x-1/2 p-4 bg-gradient-to-br from-yellow-500 to-orange-600 hover:from-orange-600 hover:to-yellow-500 text-white rounded-full shadow-lg transition-transform hover:scale-110"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              class="w-6 h-6"
            >
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6l4 2" />
            </svg>
          </button>

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
          class="w-full max-w-lg mx-auto mt-6 p-4 bg-gray-900 rounded-lg shadow-lg transition-all duration-500"
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

    <!-- Game Creation Section -->
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

    <!-- Active Games Section -->
        <div class="relative w-full mt-6 px-6 overflow-hidden flex-grow">
          <h2 class="text-center text-2xl font-bold text-neon-purple mb-4">🔥 Active Games</h2>
          <div
            class="scroll-container flex overflow-x-auto no-scrollbar snap-x snap-mandatory gap-4"
            id="carousel"
          >
            <div
              :for={game <- @active_games}
              :if={game.creator_deposit_confirmed}
              class="min-w-[250px] md:min-w-[300px] flex-shrink-0 bg-gray-700 p-4 rounded-lg shadow-lg snap-start"
            >
              <p class="text-gray-500 text-xs">🆔 Game ID: {game.id}</p>
              <p class="text-gray-500 text-xs">
                🕒 Created At: {Timex.format!(game.inserted_at, "{0D}-{0M}-{YYYY} {h24}:{m}:{s}")} UTC
              </p>
              <p class="text-neon-green font-bold truncate">🎭 Player: {game.player_wallet}</p>
              <p :if={not is_nil(game.challenger_wallet)} class="text-neon-yellow font-bold truncate">
                🥊 Challenger: {game.challenger_wallet}
              </p>
              <p class="text-neon-blue font-bold">💰 Bet: {game.bet_amount} ETH</p>
              <p class="text-gray-400 text-sm">{game.status}</p>
              <button
                :if={game.result == "pending" && (game.challenger_wallet == nil && @wallet_connected)}
                phx-click="join_game"
                phx-value-id={game.id}
                phx-value-balance={@wallet_balance}
                class="w-full mt-3 p-2 rounded-lg bg-neon-purple hover:bg-neon-green text-black font-bold transition"
              >
                ⚔️ Join Game
              </button>
              <button
                :if={
                  game.result == "pending" &&
                    (game.creator_deposit_confirmed &&
                       game.challenger_deposit_confirmed &&
                       @wallet_address in [game.player_wallet, game.challenger_wallet])
                }
                phx-click="flip_coin"
                phx-value-id={game.id}
                class="w-full mt-3 p-2 rounded-lg bg-neon-blue hover:bg-neon-green text-black font-bold transition"
              >
                🎲 Flip Coin
              </button>
            </div>
          </div>
        </div>
      </div>
      <!-- Fixed Carousel Controls -->
      <!-- Updated Navigation Menu -->
      <div class="fixed top-1/2 transform -translate-y-1/2 left-4 z-50">
        <button
          onclick="scrollToSide('left')"
          class="p-4 bg-gradient-to-r from-gray-900 to-neon-purple hover:from-neon-green hover:to-gray-900 text-white rounded-l-full shadow-lg transform transition-all hover:scale-110"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-6 w-6"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
        </button>
      </div>
      <div class="fixed top-1/2 transform -translate-y-1/2 right-4 z-50">
        <button
          onclick="scrollToSide('right')"
          class="p-4 bg-gradient-to-r from-gray-900 to-neon-green hover:from-neon-purple hover:to-gray-900 text-white rounded-r-full shadow-lg transform transition-all hover:scale-110"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-6 w-6"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
          </svg>
        </button>
      </div>

    <!-- Footer -->
      <footer class="mt-auto p-4 bg-gray-900 text-center text-gray-400">
        <div class="flex justify-center gap-2">
          <p>🚀 Powered by <span class="text-neon-purple font-bold">ETH</span></p>
          <span>✨ Play Smart. Win Big! 🎲</span>
        </div>
      </footer>

      <script>
        function scrollToSide(direction) {
          const carousel = document.getElementById("carousel");
          const cardWidth = carousel.firstElementChild.offsetWidth + 16; // Card width + gap (16px)

          if (direction === "left") {
            carousel.scrollBy({ left: -cardWidth, behavior: "smooth" });
          } else if (direction === "right") {
            carousel.scrollBy({ left: cardWidth, behavior: "smooth" });
          }
        };
      </script>
      <script>
          function triggerCoinFlip() {
        const coin = document.getElementById("coin");
        const resultContainer = document.getElementById("coin-result");
        const results = ["Heads", "Tails"];
        const randomResult = results[Math.floor(Math.random() * results.length)];

        // Reset result display
        resultContainer.classList.add("hidden");
        resultContainer.innerText = "";

        // Show the coin and start the animation
        coin.classList.remove("hidden");
        coin.style.animation = "none"; // Reset animation
        void coin.offsetWidth; // Trigger reflow
        coin.style.animation = "coinFlip 2s linear forwards";

        // Show result after the animation ends
        setTimeout(() => {
        coin.classList.add("hidden");
        resultContainer.innerText = randomResult;
        resultContainer.classList.remove("hidden");

        // Hide result after a few seconds
        setTimeout(() => {
          resultContainer.classList.add("hidden");
        }, 3000);
        }, 2000);
        }

            // Example trigger for programmatic use
            document.addEventListener("phx:coin-flip", () => {
              triggerCoinFlip();
            });
      </script>
    </div>
    """
  end

  defp status_by_challenger_deposit(%{creator_deposit_confirmed: true}, :challenger),
    do: "⚔️ Ready to Flip"

  defp status_by_challenger_deposit(_, :creator), do: "🎯 Waiting for challenger"
end
