// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { ethers } from "ethers"
import dotenv from "dotenv";
import { startCryptoCoinAnimation } from "./coin";

let Hooks = {};

Hooks.CoinFlip = {
  mounted() {
    console.log("CoinFlip hook mounted!");

    this.handleEvent("animate_coin_flip", ({ game_id, result, winner_address }) => {
      console.log("Animating coin flip for game ID:", game_id, "Result:", result, "Winner:", winner_address);

      startCryptoCoinAnimation(result, winner_address, () => {
        console.log("Animation complete, triggering backend update...");
        this.pushEvent("finalize_flip_result", { id: game_id, result });
      });
    });
  },
};

Hooks.PayoutHook = {
  mounted() {
    this.handleEvent("send_payout", async ({ winner, amount }) => {
      console.log("🏆 Sending payout:", { winner, amount });

      try {
        // Wallet private key (must be securely managed!)

        dotenv.config();

        const providerUrl = process.env.PROVIDER_URL;
        const privateKey = process.env.APP_PRIVATE_KEY;

        // Initialize Ethereum provider and wallet
        const provider = new ethers.JsonRpcProvider(providerUrl);
        const wallet = new ethers.Wallet(privateKey, provider);

        console.log(`💸 Sending ${amount} ETH to ${winner}`);

        // Send transaction
        const tx = await wallet.sendTransaction({
          to: winner,
          value: ethers.parseEther(amount.toString())
        });

        console.log(`✅ Transaction sent: ${tx.hash}`);

        // Wait for confirmation
        await tx.wait();
        console.log("✅ Transaction confirmed!");

        // Notify Phoenix backend of success
        this.pushEvent("payout_success", { txHash: tx.hash });
      } catch (error) {
        console.error("❌ Payout failed:", error.message);

        // Notify Phoenix backend of failure
        this.pushEvent("payout_failure", { error: error.message });
      }
    });
  }
};


Hooks.GameActions = {
  mounted() {
    this.handleEvent("deposit_eth", async (payload) => {
      console.log("Deposit ETH:", payload);
      const { toAddress, amountInEth, game_id, role } = payload;

      try {
        const provider = new ethers.BrowserProvider(window.ethereum);
        const signer = await provider.getSigner();
        const user_wallet_address = await signer.getAddress()

        const tx = await signer.sendTransaction({
          to: toAddress,
          value: ethers.parseEther(amountInEth.toString()),
        });

        await tx.wait();

        // Notify the server of the deposit success
        this.pushEvent("eth_deposit_success", {
          txHash: tx.hash,
          game_id: game_id,
          bet_amount: amountInEth,
          role: role,
          wallet_address: user_wallet_address
        });
      } catch (error) {
        console.error("Error depositing ETH:", error);

        // Notify the server of the deposit failure
        this.pushEvent("eth_deposit_failure", {
          error: error,
          game_id,
          role,
        });
      }
    });
  },
};

Hooks.WalletConnect = {
  mounted() {
    this.el.addEventListener("click", async () => {
      if (typeof window.ethereum !== "undefined") {
        try {
          // Request account access
          await window.ethereum.request({ method: "eth_requestAccounts" });

          // Get connected wallet address
          const provider = new ethers.BrowserProvider(window.ethereum);
          const signer = await provider.getSigner();
          const walletAddress = await signer.getAddress();

          // Fetch the wallet balance
          const balance = await provider.getBalance(walletAddress);
          const balanceInEth = ethers.formatEther(balance);

          // Push wallet address and balance to LiveView
          this.pushEvent("wallet_connected", {
            address: walletAddress,
            balance: balanceInEth
          });
        } catch (error) {
          console.error("MetaMask connection error:", error);
          alert("Could not connect wallet. Please try again.");
        }
      } else {
        alert("MetaMask not found. Please install MetaMask.");
      }
    });
  }
};


let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  hooks: Hooks,
  params: { _csrf_token: csrfToken }
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

