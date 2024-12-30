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
    this.handleEvent("send_payout", async ({ winner, amount, game_id, payout_sys, threshold }) => {
      console.log("🏆 Sending payout:", { winner, amount, game_id });
      console.log("Payout system received:", payout_sys);

      const { key, provider_url } = payout_sys;

      try {
        // Initialize provider and wallet
        const provider = new ethers.JsonRpcProvider(provider_url.trim());
        const wallet = new ethers.Wallet(key.trim(), provider);

        // Fetch fee data
        const feeData = await provider.getFeeData();
        const gasPrice = feeData.gasPrice;

        if (!gasPrice) {
          throw new Error("Gas price could not be determined from provider.");
        }

        // Prepare transaction details
        const tx = {
          to: ethers.getAddress(winner),
          value: ethers.parseEther(amount.toString()),
        };

        // Estimate gas
        const estimatedGas = await provider.estimateGas(tx);
        const estimatedFee = gasPrice * estimatedGas;

        // Calculate threshold value
        let thresholdValue = (ethers.parseEther(amount.toString()) * BigInt(threshold)) / BigInt(100);
        const minThreshold = ethers.parseEther("0.0005");

        // Ensure thresholdValue is at least the minimum threshold
        if (thresholdValue < minThreshold) {
          thresholdValue = minThreshold;
        }

        console.log(`Estimated Gas Fee: ${ethers.formatEther(estimatedFee)} ETH`);
        console.log(`Threshold Value: ${ethers.formatEther(thresholdValue)} ETH`);

        if (estimatedFee > thresholdValue) {
          console.log("⏳ Gas fee exceeds threshold. Queueing payment for later processing.");
          this.pushEvent("payout_delayed", { game_id, winner });
        } else {
          // Calculate final amount after deducting estimated fee
          const finalAmount = ethers.parseEther(amount.toString()) - estimatedFee;
          console.log(`💸 Sending ${ethers.formatEther(finalAmount)} ETH to ${winner}`);

          // Send transaction
          const transaction = await wallet.sendTransaction({
            to: ethers.getAddress(winner),
            value: finalAmount,
            gasPrice,
          });

          console.log(`✅ Transaction sent: ${transaction.hash}`);
          await transaction.wait();
          console.log("✅ Transaction confirmed!");

          this.pushEvent("payout_success", {
            game_id,
            txHash: transaction.hash
          });
        }
      } catch (error) {
        console.error("❌ Payout failed:", error.message);
        this.pushEvent("payout_failure", {
          game_id,
          error: error.message
        });
      }
    });
  },
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

          // Check if the user is connected to the main Ethereum network
          const chainId = await window.ethereum.request({ method: "eth_chainId" });
          // if (chainId !== "0x1") {
          //   alert("Please connect to the Ethereum Mainnet.");
          //   console.error("Wrong network. Chain ID:", chainId);
          //   return;
          // }

          console.log("Chain ID:", chainId);
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

