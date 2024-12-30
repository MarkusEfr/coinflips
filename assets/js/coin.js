import anime from "animejs";

export const startCryptoCoinAnimation = (result, winnerAddress, onComplete) => {
    console.log("Starting coin animation with result:", result);

    const coinContainer = document.getElementById("coin-container");
    const coinElement = document.getElementById("coin");
    const winnerElement = document.getElementById("winner-address");
    const treasureElement = document.getElementById("treasure");

    if (!coinContainer || !coinElement || !winnerElement || !treasureElement) {
        console.error("Required elements not found!");
        return;
    }

    // Ensure the container is visible
    coinContainer.classList.remove("hidden");
    winnerElement.classList.add("hidden"); // Hide winner initially
    treasureElement.classList.add("hidden"); // Hide treasure initially

    // Set initial styles for the coin to make it visible during spinning
    coinElement.style.backgroundColor = "#FFD700"; // Gold background
    coinElement.style.border = "4px solid #FF5733"; // Orange border
    coinElement.style.borderRadius = "50%"; // Circular coin shape

    // Define the SVG icons
    const headSVG = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" fill="none" width="100" height="100">
  <path d="M16 64L40 20L64 60L88 20L112 64H16Z" fill="#FFD700" stroke="#FF5733" stroke-width="3" />
  <circle cx="40" cy="16" r="6" fill="#FF6347" stroke="#FFD700" stroke-width="2" />
  <circle cx="64" cy="10" r="7" fill="#4682B4" stroke="#FFD700" stroke-width="2" />
  <circle cx="88" cy="16" r="6" fill="#32CD32" stroke="#FFD700" stroke-width="2" />
  <rect x="16" y="64" width="96" height="12" fill="#4B0082" stroke="#FFD700" stroke-width="2" />
  <path d="M20 80H108" stroke="#FFFFFF" stroke-width="2" stroke-dasharray="4 2" />
  <text x="64" y="104" fill="#FFFFFF" font-size="14px" text-anchor="middle" font-weight="bold">
    HEADS
  </text>
</svg>
`;

    const tailsSVG = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" fill="none" width="100" height="100">
  <rect x="32" y="48" width="64" height="40" fill="#FFD700" stroke="#FF5733" stroke-width="4" />
  <rect x="40" y="28" width="48" height="20" fill="#FFD700" stroke="#FF4500" stroke-width="3" />
  <path d="M48 28L64 12L80 28" stroke="#00FA9A" stroke-width="3" />
  <rect x="30" y="88" width="68" height="12" fill="#FFD700" stroke="#FF5733" stroke-width="2" />
  <path d="M40 28L64 12L88 28" stroke="#FF4500" stroke-width="3" />
  <text x="64" y="110" fill="#FFFFFF" font-size="12px" text-anchor="middle" font-weight="bold">
    TAILS
  </text>
</svg>
`;

    // Continuous spinning animation
    const spinDuration = 1000; // Total spinning time
    const spinInterval = 300; // Time per spin iteration

    let spins = spinDuration / spinInterval; // Number of spins

    const spin = () => {
        if (spins > 0) {
            anime({
                targets: "#coin",
                rotateY: "+=360", // Rotate 360 degrees
                duration: spinInterval,
                easing: "linear",
                complete: () => {
                    spins--;
                    spin(); // Continue spinning
                },
            });
        } else {
            // Final animation to stop and show result
            anime({
                targets: "#coin",
                rotateY: "+=360",
                duration: 1000, // Slow final spin
                easing: "easeOutCubic",
                complete: () => {
                    console.log("Coin animation complete. Showing result:", result);

                    // Show the result after spinning
                    coinElement.innerHTML = result === "Heads" ? headSVG : tailsSVG;
                    coinElement.style.backgroundColor = "#FFD700"; // Keep gold background
                    coinElement.style.border = "4px solid #FF5733"; // Keep border

                    // Display the winner and treasure
                    winnerElement.innerHTML = `Winner: ${winnerAddress}`;
                    treasureElement.innerHTML = "💰 Treasure Unlocked!";
                    winnerElement.classList.remove("hidden");
                    treasureElement.classList.remove("hidden");

                    // Hide everything after 4 seconds
                    setTimeout(() => {
                        coinContainer.classList.add("hidden");
                        if (onComplete) onComplete(); // Trigger callback if provided
                    }, 4000);
                },
            });
        }
    };

    // Start the spinning animation
    spin();
};
