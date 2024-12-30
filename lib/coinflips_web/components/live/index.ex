defmodule CoinflipsWeb.Live.Index do
  use CoinflipsWeb, :live_view

  alias Coinflips.Payouts
  import Coinflips.Games, only: [parse_amount: 1, filter_games: 1]

  @topic "games"
  @min_bet 0.001
  @app_wallet_address "0xa1207Ea48191889e931e11415cE13DF5d9654852"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: CoinflipsWeb.Endpoint.subscribe(@topic)

    default_games =
      filter_games(%{"status" => ["waiting", "ready", "completed"]})

    {:ok,
     assign(socket,
       wallet_connected: false,
       wallet_address: nil,
       wallet_balance: 0.0,
       active_games: default_games,
       paginated_games: default_games |> paginate_games(1, 6),
       current_page: 1,
       games_per_page: 6,
       total_pages: calculate_total_pages(default_games, 6),
       bet_amount: nil,
       tip_list: [],
       private_game: false,
       show_notifications: false,
       filter_min_bet: nil,
       filter_max_bet: nil,
       filter_status: ["waiting", "ready", "completed"],
       selected_section: :home,
       game_history: []
     )}
  end

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
    filtered_games = filter_games(params)

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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen bg-gradient-to-b from-black via-gray-950 to-black text-yellow-300 font-mono">

    <!-- Sidebar -->
      <aside class="w-16 bg-gradient-to-b from-gray-900 to-gray-800 flex flex-col items-center py-6 shadow-lg relative">
        <nav class="space-y-6">
          <button
            phx-click="select_section"
            phx-value-section="home"
            class="group flex items-center justify-center w-12 h-12 rounded-full bg-gray-800 hover:bg-yellow-500 transition"
          >
            <span class="text-white text-xl">🏠</span>
            <span class="hidden group-hover:block text-sm mt-2 text-yellow-300">Home</span>
          </button>

          <button
            phx-click="select_section"
            phx-value-section="dashboard"
            class="group flex items-center justify-center w-12 h-12 rounded-full bg-gray-800 hover:bg-yellow-500 transition"
          >
            <span class="text-white text-xl">📊</span>
            <span class="hidden group-hover:block text-sm mt-2 text-yellow-300">Dashboard</span>
          </button>

          <button
            phx-click="select_section"
            phx-value-section="profile"
            class="group flex items-center justify-center w-12 h-12 rounded-full bg-gray-800 hover:bg-yellow-500 transition"
          >
            <span class="text-white text-xl">👤</span>
            <span class="hidden group-hover:block text-sm mt-2 text-yellow-300">Profile</span>
          </button>

          <div class="relative">
            <button
              class="group flex items-center justify-center w-12 h-12 rounded-full bg-gray-800 hover:bg-yellow-500 transition"
              phx-click="select_section"
              phx-value-section="notifications"
            >
              <span class="text-white text-xl">🔔</span>
              <span class="hidden group-hover:block text-sm mt-2 text-yellow-300">Notifications</span>
              <!-- Badge -->
              <span
                :if={@tip_list != []}
                class="absolute top-1 right-1 bg-red-600 text-white text-xs rounded-full px-1.5 py-0.5 font-bold"
              >
                {@tip_list |> length}
              </span>
            </button>
            <!-- Notifications Popup -->
            <div
              :if={@tip_list != []}
              id="notifications-popup"
              class="absolute top-0 left-14 bg-gray-800 text-yellow-300 px-4 py-2 rounded-md shadow-lg z-50 animate-slide-in"
            >
              <div
                :for={tip <- @tip_list}
                class="mb-2 text-sm bg-gray-700 px-3 py-2 rounded-md shadow-md"
              >
                {tip.message}
              </div>
            </div>
          </div>
        </nav>
      </aside>

    <!-- Main Content -->
      <div class="flex-grow flex flex-col">
        <!-- Header -->
        <header class="flex justify-between items-center px-6 py-4">
          <h1>🎲 Coinflips Panel</h1>
          <div class="flex items-center space-x-4">
            <div class="flex items-center bg-gray-700 px-4 py-2 rounded-lg">
              <p class="text-yellow-400 truncate">🔑 {@wallet_address || "Not Connected"}</p>
              <p class="ml-4 text-neon-green font-bold">{@wallet_balance || "0.0"} ETH</p>
            </div>
            <button
              id="wallet-connect"
              phx-hook="WalletConnect"
              disabled={@wallet_connected}
              class="font-bold"
            >
              {if @wallet_connected, do: "🛑 Wallet Connected", else: "🔗 Connect Wallet"}
            </button>
          </div>
        </header>

    <!-- Dynamic Content -->
        <main class="flex-grow px-6 py-4">
          {cond do
            @selected_section in [:home, "home"] -> render_home(assigns)
            @selected_section in [:dashboard, "dashboard"] -> render_dashboard(assigns)
            @selected_section in [:profile, "profile"] -> render_profile(assigns)
            @selected_section in [:notifications, "notifications"] -> render_notifications(assigns)
          end}
        </main>

        <footer class="mt-auto p-4 bg-gray-900 text-center text-gray-400">
          <div class="flex justify-center gap-2">
            <p>🚀 Powered by <span class="text-neon-purple font-bold">ETH</span></p>
            <span>✨ Play Smart. Win Big! 🎲</span>
          </div>
        </footer>
      </div>
    </div>
    """
  end

  defp render_home(assigns) do
    ~H"""
    <div id="home-container" phx-hook="GameActions">
      <!-- Filters and Game Creation at Header -->
      <div class="flex justify-between items-center mb-6">
        <!-- Filters -->
        <form phx-change="filter_games" class="flex space-x-4">
          <div>
            <label class="block text-sm text-yellow-400">💰 Min Bet</label>
            <input
              type="number"
              name="min_bet"
              step="0.001"
              value={@filter_min_bet}
              class="bg-gray-700 px-4 py-2 rounded-lg text-white focus:ring focus:ring-yellow-500"
              placeholder="e.g., 0.001"
            />
          </div>

          <div>
            <label class="block text-sm text-yellow-400">💎 Max Bet</label>
            <input
              type="number"
              name="max_bet"
              step="0.1"
              value={@filter_max_bet}
              class="bg-gray-700 px-4 py-2 rounded-lg text-white focus:ring focus:ring-yellow-500"
              placeholder="e.g., 0.01"
            />
          </div>

          <div>
            <label class="block text-xs font-medium text-yellow-400 mb-1">📊 Status</label>
            <select
              name="status[]"
              multiple
              class="bg-gray-800 text-yellow-300 border border-gray-700 focus:ring focus:ring-yellow-500 rounded-md px-2 py-1 text-sm w-full shadow-sm"
            >
              <option value="waiting" selected={Enum.member?(@filter_status, "waiting")}>
                🎯 Waiting
              </option>
              <option value="ready" selected={Enum.member?(@filter_status, "ready")}>
                ⚔️ Ready
              </option>
              <option value="completed" selected={Enum.member?(@filter_status, "completed")}>
                🏆 Completed
              </option>
            </select>
          </div>
        </form>

        <!-- Game Creation -->
        <div>
          <form phx-change="validate_bet" phx-submit="create_game" class="space-y-2">
            <input
              type="number"
              step="0.001"
              min={min_bet()}
              name="bet_amount"
              class="bg-gray-700 px-4 py-2 rounded-lg text-white focus:ring focus:ring-neon-green"
              placeholder={"Enter your wager (Min: #{min_bet()} ETH)"}
            />
            <input type="hidden" name="balance" value={@wallet_balance} />
            <label class="flex items-center space-x-2">
              <input type="checkbox" name="private_game" class="h-4 w-4 text-yellow-500" />
              <span class="text-yellow-400">Private Bet</span>
            </label>
            <button class="flex items-center space-x-1 bg-gradient-to-r from-yellow-500 to-red-500 px-3 py-2 rounded-md text-black font-bold hover:scale-105 transition-transform">
              🎯 <span>Start</span>
            </button>
          </form>
        </div>
      </div>
      <div
        id="coin-container"
        class="hidden fixed inset-0 flex flex-col items-center justify-center bg-black bg-opacity-75 z-50"
      >
        <div
          id="coin"
          class="coin w-48 h-48 bg-gray-800 text-white text-4xl font-extrabold flex items-center justify-center rounded-full shadow-lg"
        >
          <!-- Result will appear here -->
        </div>
        <p id="winner-address" class="hidden text-neon-green text-lg font-bold mt-4 text-center">
          <!-- Winner address will appear here -->
        </p>
        <p id="treasure" class="hidden text-yellow-400 text-lg font-bold mt-2 text-center">
          <!-- Treasure message will appear here -->
        </p>
      </div>
      <!-- Active Games -->
      <div class="flex-grow px-6 py-4" id="active-games" phx-hook="CoinFlip">
        <h2 class="text-2xl font-bold text-yellow-400 mb-4">🔥 Active Games</h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          <div
            :for={game <- @paginated_games}
            class="bg-gradient-to-b from-gray-800 via-gray-900 to-gray-800 p-4 rounded-lg shadow-md hover:shadow-lg hover:scale-105 transition-transform"
          >
            <p class="text-sm text-yellow-400">🆔 Bet ID: {game.id}</p>
            <p class="text-sm text-yellow-500">💰 Bet: {game.bet_amount} ETH</p>
            <p class="text-sm text-neon-green">🎭 Player: {game.player_wallet}</p>
            <p :if={game.challenger_wallet} class="text-sm text-neon-blue">
              🥊 Challenger: {game.challenger_wallet}
            </p>
            <p class="text-sm text-yellow-400">
              📅 Created At: {game.inserted_at |> Timex.format!("{0D}-{0M}-{YYYY} {h24}:{m}:{s}")}
            </p>
            <p class="text-sm text-yellow-500">📊 Status: {game.status}</p>

            <!-- Join Game Button -->
            <div id={"join-button-#{game.id}"} class="flex justify-end space-x-2 mt-2">
              <button
                :if={@wallet_connected and game.result == "pending" and game.challenger_deposit_confirmed in [false, nil]}
                id={"join-#{game.id}"}
                class="flex items-center justify-center space-x-1 bg-gradient-to-r from-green-500 to-blue-500 px-2 py-1 rounded-full text-white font-bold shadow-md hover:from-blue-500 hover:to-green-500 transition-transform transform hover:scale-110"
                phx-click="join_game"
                title="Join this game"
                phx-value-id={game.id}
                phx-value-balance={@wallet_balance}
              >
                ⚔️ <span class="md:block">Join</span>
              </button>

              <button
                :if={
                  game.result == "pending" and
                    game.creator_deposit_confirmed and
                    game.challenger_deposit_confirmed and
                    @wallet_address in [game.player_wallet, game.challenger_wallet]
                }
                phx-click="trigger_coin_flip"
                phx-value-id={game.id}
                id={"flip-coin-#{game.id}"}
                class="flex items-center justify-center space-x-1 bg-gradient-to-r from-indigo-500 to-purple-500 px-2 py-1 rounded-full text-white font-bold shadow-md hover:from-purple-500 hover:to-indigo-500 transition-transform transform hover:scale-110"
                title="Flip the coin"
              >
                🎲 <span class="md:block">Flip</span>
              </button>
            </div>
          </div>
        </div>
      </div>
      <div class="fixed bottom-16 left-1/2 transform -translate-x-1/2 flex flex-col items-center space-y-2">
    <!-- Progress Bar -->
    <div class="relative w-3/4 h-1 bg-gray-800 rounded-full">
    <div
      class="absolute top-0 left-0 h-1 bg-neon-green rounded-full transition-all"
      style={"width: #{round(@current_page / @total_pages * 100)}%;"}
    ></div>
    </div>
    <!-- Navigation -->
    <div class="flex items-center space-x-4">
    <button
      :if={@current_page > 1}
      phx-click="change_page"
      phx-value-page={@current_page - 1}
      class="w-8 h-8 flex items-center justify-center text-neon-green border border-gray-700 rounded-full hover:bg-gray-800 transition-all"
    >
      ◀
    </button>
    <p class="text-sm text-gray-400">
      Page <span class="text-neon-green">{@current_page}</span> of <span class="text-neon-green">{@total_pages}</span>
    </p>
    <button
      :if={@current_page < @total_pages}
      phx-click="change_page"
      phx-value-page={@current_page + 1}
      class="w-8 h-8 flex items-center justify-center text-neon-green border border-gray-700 rounded-full hover:bg-gray-800 transition-all"
    >
      ▶
    </button>
    </div>
    </div>

    </div>
    """
  end

  defp render_dashboard(assigns) do
    ~H"""
    <div>
      <h2 class="text-2xl font-bold text-yellow-400 mb-4">📊 Games Dashboard</h2>
      <p>Total Active Games: {length(@active_games)}</p>
      <!-- Add additional dashboard analytics -->
    </div>
    """
  end

  defp render_profile(assigns) do
    ~H"""
    <div>
      <h2 class="text-2xl font-bold text-yellow-400 mb-4">👤 User Profile</h2>
      <p>Wallet Address: {@wallet_address || "Not Connected"}</p>
      <p>Balance: {@wallet_balance || "0.0"} ETH</p>
      <h3 class="mt-6 text-yellow-400">Game History:</h3>
      <ul>
        <%= for game <- @game_history do %>
          <li>Game ID: {game.id} | Status: {game.status}</li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp render_notifications(assigns) do
    ~H"""
    <div>
      <h2 class="text-2xl font-bold text-yellow-400 mb-4">🔔 Notifications</h2>
      <%= for notification <- @tip_list do %>
        <div class="p-3 bg-gray-800 rounded-md shadow-md mb-2">
          <p>{notification.message}</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Handle pagination events
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

  # Remove a tip  @impl true
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

  # Bet Validation
  def handle_event("validate_bet", %{"bet_amount" => bet_amount, "balance" => balance}, socket) do
    bet_amount = bet_amount |> parse_amount()

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

  # Wallet Connection
  @impl true
  def handle_event("wallet_connected", %{"address" => address, "balance" => balance}, socket) do
    balance = String.to_float(balance)

    {:noreply,
     add_tip(socket, "🔗 Wallet connected! Ready to play.")
     |> assign(wallet_connected: true, wallet_address: address, wallet_balance: balance)}
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

        CoinflipsWeb.Endpoint.broadcast(
          @topic,
          "update_games",
          {:update_game, new_game, is_new?: true}
        )

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
      CoinflipsWeb.Endpoint.broadcast(
        @topic,
        "update_games",
        {:update_game, updated_game, is_new?: false}
      )

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
      CoinflipsWeb.Endpoint.broadcast(
        @topic,
        "update_games",
        {:update_game, new_game, is_new?: true}
      )

      {:noreply, socket |> add_tip("💰 Deposit confirmed for game #{game_id}.")}
    end
  end

  def handle_event(
        "eth_deposit_failure",
        %{"error" => %{"shortMessage" => short_message}, "game_id" => game_id, "role" => role},
        socket
      ) do
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

    # CoinflipsWeb.Endpoint.broadcast(@topic, "update_games", {:update_game, updated_game})

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
  def handle_event("toggle_notifications", _, socket) do
    {:noreply, assign(socket, show_notifications: !socket.assigns.show_notifications)}
  end

  @impl true
  def handle_event("close_notifications", _, socket) do
    {:noreply, assign(socket, show_notifications: false)}
  end

  @impl true
  def handle_event("filter_games", params, socket) do
    filtered_games = filter_games(params)

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

  # Helper function to calculate total pages
  defp calculate_total_pages(games, games_per_page) do
    total = div(length(games) + games_per_page - 1, games_per_page)
    # Ensure there is always at least 1 page
    max(total, 1)
  end

  # Paginate the games based on the current page
  defp paginate_games(games, page, games_per_page) do
    games
    |> Enum.chunk_every(games_per_page)
    |> Enum.at(page - 1, [])
  end

  defp visible_pages(current_page, total_pages, max_visible_pages \\ 5) do
    # Always include the first and last pages
    edge_pages = [1, total_pages]

    # Calculate the range of pages around the current page
    middle_start = max(2, current_page - div(max_visible_pages - 1, 2))
    middle_end = min(total_pages - 1, current_page + div(max_visible_pages - 1, 2))

    # Create the middle range as a list of integers
    middle_range = Enum.to_list(middle_start..middle_end)

    # Combine edge and middle pages, removing duplicates and invalid numbers
    (edge_pages ++ middle_range)
    |> Enum.uniq()
    # Ensure pages are valid
    |> Enum.filter(&(&1 > 0 and &1 <= total_pages))
    |> Enum.sort()
  end

  defp add_tip(socket, message) do
    tip_id = :erlang.system_time(:millisecond)

    # Add tip to the tip list
    updated_tips = [%{id: tip_id, message: message} | socket.assigns.tip_list]

    # Auto-remove the tip after a delay without affecting other processes
    Process.send_after(self(), {:remove_tip, tip_id}, 1750)

    assign(socket, tip_list: updated_tips)
  end

  defp min_bet(), do: @min_bet

  defp app_wallet_address(), do: @app_wallet_address

  defp status_by_challenger_deposit(%{creator_deposit_confirmed: true}, :challenger),
    do: "⚔️ Ready to Flip"

  defp status_by_challenger_deposit(_, :creator), do: "🎯 Waiting for challenger"
end
