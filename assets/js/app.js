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

async function payoutWinner(winnerAddress, totalBetAmountInEth) {
  try {
    const tx = await appWallet.sendTransaction({
      to: winnerAddress,
      value: ethers.parseEther(totalBetAmountInEth),
    });

    await tx.wait();
    console.log(`Paid ${totalBetAmountInEth} ETH to winner: ${winnerAddress}`);
  } catch (error) {
    console.error("Error sending payout:", error);
    throw new Error("Failed to send payout.");
  }
}


let Hooks = {};

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

