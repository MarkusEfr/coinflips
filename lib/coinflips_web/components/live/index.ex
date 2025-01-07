defmodule CoinflipsWeb.Live.Index do
  @moduledoc """
  Index LiveView for Coinflips
  """
  use CoinflipsWeb, :live_view

  import CoinflipsWeb.Endpoint, only: [subscribe: 1]

  alias Coinflips.{Notifications, Games}
  alias CoinflipsWeb.Handlers.{EventCommandor, ListenerObserver}

  @topic "games"
  @notify_topic "notifications"

  @impl true
  def handle_event(event, params, socket) do
    EventCommandor.handle_event(event, params, socket)
  end

  @impl true
  def handle_info(msg, socket) do
    ListenerObserver.handle_info(msg, socket)
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      subscribe(@notify_topic)
      subscribe(@topic)
    end

    default_games = Games.filter_games(%{"status" => ["waiting", "ready", "completed"]})

    {:ok,
     assign(socket,
       wallet_connected: false,
       wallet_address: nil,
       wallet_balance: 0.0,
       default_games: default_games,
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
       game_history: [],
       grouped_history: %{},
       group_by: "day",
       grouped_notifications: [],
       notifications: [],
       # Initialize lock map
       locked_games: %{}
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
            @selected_section in [:notifications, "notifications"] -> render_system_messages(assigns)
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
            /> <input type="hidden" name="balance" value={@wallet_balance} />
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
    <!-- If game is locked -->
    <div
      :if={Map.get(@locked_games, game.id)}
      class="flex items-center justify-center space-x-2 text-red-500 font-bold"
    >
      <span class="animate-spin rounded-full h-5 w-5 border-t-2 border-b-2 border-red-500"></span>
      <span>Locked</span>
    </div>

    <div id={"join-button-#{game.id}"} class="flex justify-end space-x-2 mt-2">
    <!-- If game is locked -->
    <div
    :if={Map.get(@locked_games, "#{game.id}")})}
    class="flex items-center justify-center space-x-2 text-red-500 font-bold"
    >
    🔒 <span>Locked</span>
    </div>

    <!-- If game is not locked -->
    <button
    :if={@wallet_connected and game.result == "pending" and game.challenger_deposit_confirmed in [false, nil] and !Map.get(@locked_games, "#{game.id}")}
    id={"join-#{game.id}"}
    class="flex items-center justify-center space-x-1 bg-gradient-to-r from-green-500 to-blue-500 px-2 py-1 rounded-full text-white font-bold shadow-md hover:from-blue-500 hover:to-green-500 transition-transform transform hover:scale-110"
    phx-click="join_game"
    title="Join this game"
    phx-value-id={game.id}
    phx-value-balance={@wallet_balance}
    >
    ⚔️ <span class="md:block">Join</span>
    </button>
    </div>


    <button
      :if={
        game.result == "pending" and
          game.creator_deposit_confirmed and
          game.challenger_deposit_confirmed and
          @wallet_address in [game.player_wallet, game.challenger_wallet] and !Map.get(@locked_games, "#{game.id}")}
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
      </div>

      <div class="fixed bottom-16 left-1/2 transform -translate-x-1/2 flex flex-col items-center space-y-2">
        <!-- Progress Bar -->
        <div class="relative w-3/4 h-1 bg-gray-800 rounded-full">
          <div
            class="absolute top-0 left-0 h-1 bg-neon-green rounded-full transition-all"
            style={"width: #{round(@current_page / @total_pages * 100)}%;"}
          >
          </div>
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
            Page <span class="text-neon-green">{@current_page}</span>
            of <span class="text-neon-green">{@total_pages}</span>
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
    """
  end

  defp render_dashboard(assigns) do
    ~H"""
    <div>
      <h2 class="text-2xl font-bold text-yellow-400 mb-4">📊 Games Dashboard</h2>

      <!-- Summary Statistics -->
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <div class="bg-gray-800 text-center p-4 rounded-lg shadow-md">
          <p class="text-yellow-400 text-lg font-bold">🎮 Total Active Games</p>
          <p class="text-white text-xl font-extrabold">{length(@default_games)}</p>
        </div>

        <div class="bg-gray-800 text-center p-4 rounded-lg shadow-md">
          <p class="text-yellow-400 text-lg font-bold">💸 Total Bets Placed</p>
          <p class="text-white text-xl font-extrabold">{total_bets(@default_games)}</p>
        </div>

        <div class="bg-gray-800 text-center p-4 rounded-lg shadow-md">
          <p class="text-yellow-400 text-lg font-bold">🪙 Total ETH Wagered</p>
          <p class="text-white text-xl font-extrabold">{total_eth_wagered(@default_games)} ETH</p>
        </div>

        <div class="bg-gray-800 text-center p-4 rounded-lg shadow-md">
          <p class="text-yellow-400 text-lg font-bold">🏆 Winning Ratio</p>
          <p class="text-white text-xl font-extrabold">
            {winning_ratio(@game_history, @wallet_address)}%
          </p>
        </div>
      </div>

      <!-- Detailed Analytics -->
      <div class="mt-6 bg-gray-800 p-6 rounded-lg shadow-lg">
        <h3 class="text-lg font-bold text-yellow-400 mb-4">📊 Detailed Analytics</h3>
        <ul class="text-sm text-yellow-300">
          <li>🎮 Most Active Player: {most_active_player(@game_history)}</li>
          <li>💰 Largest Bet: {largest_bet(@active_games)} ETH</li>
          <li>📊 Most Played Status: {most_played_status(@game_history)}</li>
          <li>🕒 Most Recent Game: {most_recent_game(@active_games)}</li>
        </ul>
      </div>
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
        {render_game_history(assigns)}
      </div>
    </div>
    """
  end

  defp winning_ratio(game_history, wallet_address) do
    total_games = length(game_history)

    won_games =
      game_history
      |> Enum.count(fn game ->
        (game.result == "Heads" and game.player_wallet == wallet_address) or
          (game.result == "Tails" and game.challenger_wallet == wallet_address)
      end)

    if total_games > 0, do: Float.round(won_games / total_games * 100, 2), else: 0.0
  end

  defp render_game_history(assigns) do
    ~H"""
    <div class="bg-black text-green-300 font-mono rounded-lg p-4 shadow-lg">
      <h2 class="text-lg font-bold text-green-400 mb-2">📜 Game History</h2>

      <form phx-change="group_by" class="mb-2">
        <label class="text-sm font-bold mr-2">Group By:</label>
        <select
          name="group_by"
          class="bg-black text-green-300 border border-green-500 rounded px-2 py-1 text-sm focus:outline-none focus:ring focus:ring-green-500"
        >
          <option value="day" selected={@group_by == "day"}>Day</option>
          <option value="status" selected={@group_by == "status"}>Status</option>
        </select>
      </form>

      <div class="overflow-y-auto max-h-96 border border-green-500 rounded p-2 bg-gray-800 no-scrollbar">
        <pre class="text-sm">
    $ fetch_game_history_grouped
    <%= for {group, games} <- @grouped_history do %>
    GROUP: {group}
    --------------------------------------------
    <%= for game <- games do %>
    <%= render_item(game, [:id, :player_wallet, :bet_amount, :status], %{
      id: "🎲 ID",
      player_wallet: "👤 Player",
      bet_amount: "💰 Bet",
      status: "📊 Status"
    }) %>
    <% end %>
    <% end %>
        </pre>
      </div>
    </div>
    """
  end

  defp render_system_messages(assigns) do
    ~H"""
    <div>
      <h2 class="text-2xl font-bold text-yellow-400 mb-4">📢 System Messages</h2>

      <p class="mb-4">
        Below are your system notifications and updates. Stay informed about the latest events and changes in the system.
      </p>

      <div class="mt-6">
        <!-- Terminal-Style Notifications Report -->
        {render_notifications(assigns)}
      </div>
    </div>
    """
  end

  defp render_notifications(assigns) do
    ~H"""
    <div class="bg-black text-green-300 font-mono rounded-lg p-4 shadow-lg mt-6">
      <h2 class="text-lg font-bold text-green-400 mb-2">📬 Notifications</h2>

      <form phx-change="group_notifications" class="mb-2">
        <label class="text-sm font-bold mr-2">Group By:</label>
        <select
          name="group_by"
          class="bg-black text-green-300 border border-green-500 rounded px-2 py-1 text-sm focus:outline-none focus:ring focus:ring-green-500"
        >
          <option value="unread?" selected={@group_by == "unread?"}>Status</option>
          <option value="date" selected={@group_by == "date"}>Date</option>
        </select>
      </form>

      <div class="overflow-y-auto max-h-96 border border-green-500 rounded p-2 bg-gray-800 no-scrollbar">
        <pre class="text-sm">
    $ fetch_notifications_grouped
    <%= for {group, notifications} <- @grouped_notifications do %>
    GROUP: {group}
    --------------------------------------------
    <%= for notification <- notifications do %>
    <%= render_item(notification, [:id, :title, :unread?, :message, :inserted_at], %{
      id: "🔔 ID",
      title: "🏷 Title",
      unread?: "📂 Unread",
      message: "📄 Message",
      inserted_at: "🕒 Date & Time"
    }) %>
    <%= if notification.unread? do %>
    > <button
      phx-click="mark_as_read"
      phx-value-id={notification.id}
      class="text-green-300 hover:text-green-500 underline focus:outline-none transition"
    >
      MARK AS READ
    </button>
    <% end %>
    <% end %>
    <% end %>
        </pre>
      </div>
    </div>
    """
  end

  defp render_item(item, fields, labels) do
    Enum.map(fields, fn field ->
      label = Map.get(labels, field, field |> Atom.to_string() |> String.capitalize())
      value = Map.get(item, field)

      case value do
        true -> "#{label}: Yes"
        false -> "#{label}: No"
        _ -> "#{label}: #{value}"
      end
    end)
    |> Enum.join(" | ")
  end

  # Total bets placed
  defp total_bets(games) do
    length(games)
  end

  # Total ETH wagered
  defp total_eth_wagered(games) do
    games
    |> Enum.reduce(Decimal.new(0), fn game, acc -> Decimal.add(acc, game.bet_amount) end)
  end

  # Most active player
  defp most_active_player(game_history) do
    game_history
    |> Enum.group_by(& &1.player_wallet)
    |> Enum.max_by(fn {_player, games} -> length(games) end, fn -> {"N/A", []} end)
    |> elem(0)
  end

  # Largest bet
  defp largest_bet(games) do
    games
    |> Enum.max_by(& &1.bet_amount, fn -> %{} end)
    |> Map.get(:bet_amount, "N/A")
  end

  # Most recent game
  defp most_recent_game(games) do
    games
    |> Enum.max_by(& &1.inserted_at, fn -> %{} end)
    |> Map.get(:id, "N/A")
  end

  defp total_wins(game_history, wallet_address) do
    Enum.count(game_history, fn game ->
      game.result in ["Heads", "Tails"] and game.player_wallet == wallet_address
    end)
  end

  defp total_losses(game_history, wallet_address) do
    Enum.count(game_history, fn game ->
      game.result in ["Heads", "Tails"] and game.challenger_wallet == wallet_address
    end)
  end

  defp total_loss_amount(game_history, wallet_address) do
    game_history
    |> Enum.filter(fn game ->
      game.result in ["Heads", "Tails"] and game.challenger_wallet == wallet_address
    end)
    |> Enum.reduce(Decimal.new(0), fn game, acc ->
      Decimal.add(acc, Decimal.new(game.bet_amount))
    end)
  end

  defp total_wins_amount(game_history, wallet_address) do
    game_history
    |> Enum.filter(fn game ->
      game.result in ["Heads", "Tails"] and game.player_wallet == wallet_address
    end)
    |> Enum.reduce(Decimal.new(0), fn game, acc ->
      Decimal.add(acc, Decimal.new(game.bet_amount))
    end)
  end

  defp most_lucky_day(game_history, wallet_address) do
    game_history
    |> Enum.filter(fn game ->
      game.result in ["Heads", "Tails"] and game.player_wallet == wallet_address
    end)
    |> Enum.group_by(fn game -> Date.to_string(game.inserted_at) end)
    |> Enum.max_by(fn {_date, games} -> length(games) end, fn -> {"N/A", []} end)
    |> elem(0)
  end

  defp derive_game_status(game) do
    cond do
      String.starts_with?(game.status, "🏆") and game.result in ["Heads", "Tails"] ->
        "completed"

      game.status == "⚔️ Ready to Flip" and game.result == "pending" ->
        "ready"

      game.status == "🎯 Waiting for challenger" and game.result == "pending" ->
        "waiting"

      true ->
        "unknown"
    end
  end

  defp games_with_status(game_history, status) do
    game_history
    |> Enum.filter(fn game ->
      derive_game_status(game) == status
    end)
    |> length()
  end

  defp most_played_status(game_history) do
    game_history
    |> Enum.group_by(& &1.status)
    |> Enum.max_by(fn {_status, games} -> length(games) end, fn -> {"None", []} end)
    |> elem(0)
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
