defmodule CoinflipsWeb.Live.Index do
  alias Coinflips.Games
  use CoinflipsWeb, :live_view

  @topic "games"

  @impl true
  def handle_event(event, params, socket) do
    CoinflipsWeb.Handlers.EventCommandor.handle_event(event, params, socket)
  end

  @impl true
  def handle_info(msg, socket) do
    CoinflipsWeb.Handlers.ListenerObserver.handle_info(msg, socket)
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: CoinflipsWeb.Endpoint.subscribe(@topic)

    default_games =
      Games.filter_games(%{"status" => ["waiting", "ready", "completed"]})

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

      <div class="mt-6">
        <!-- Terminal-Style Game History Report -->
        <%= render_terminal(assigns) %>
      </div>
    </div>
    """
  end

  defp winning_ratio(game_history, wallet_address) do
    total_games = length(game_history)
    IO.inspect(total_games, label: "total_games")

    won_games =
      game_history
      |> Enum.count(fn game ->
        (game.result == "Heads" and game.player_wallet == wallet_address) or
          (game.result == "Tails" and game.challenger_wallet == wallet_address)
      end)

    if total_games > 0, do: Float.round(won_games / total_games * 100, 2), else: 0.0
  end

  defp render_terminal(assigns) do
    ~H"""
    <div class="bg-black text-green-300 font-mono rounded-lg p-4 shadow-lg">
      <!-- Report Header -->
      <div class="border-b border-green-500 pb-2 mb-4">
        <h2 class="text-lg font-bold">
        📜 Game History Report</h2>
        <pre class="text-sm">
        ┌───────────────────────────────────────────┐
        │ Total Games Played: {length(@game_history)}               │
        │ Total ETH Bet: {@game_history |> Enum.reduce(Decimal.new(0), fn game, acc -> Decimal.add(acc, Decimal.new(game.bet_amount)) end)} ETH  │
        │ Winning Ratio: {winning_ratio(@game_history, @wallet_address)}%                     │
        │ Most Played Status: {most_played_status(@game_history)}            │
        └───────────────────────────────────────────┘
        </pre>
      </div>

      <!-- Analytics Breakdown -->
      <div class="overflow-y-auto max-h-96 border border-green-500 rounded p-2 bg-black">
        <h3 class="text-sm font-bold mb-2">🖥️ Detailed Analytics</h3>
        <p class="text-sm">Games Waiting: {games_with_status(@game_history, "waiting")}</p>
        <p class="text-sm">Games Ready: {games_with_status(@game_history, "ready")}</p>
        <p class="text-sm">Games Completed: {games_with_status(@game_history, "completed")}</p>
      </div>
    </div>
    """
  end

  defp games_with_status(game_history, status) do
    game_history
    |> Enum.filter(fn game -> game.status == status end)
    |> length()
  end

  defp most_played_status(game_history) do
    game_history
    |> Enum.group_by(& &1.status)
    |> Enum.max_by(fn {_status, games} -> length(games) end, fn -> {"None", []} end)
    |> elem(0)
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

  defp min_bet(), do: @min_bet
end
