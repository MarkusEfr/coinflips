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

    // Reset the coin's content and styles
    coinElement.innerHTML = ""; // Clear previous result
    coinElement.style.backgroundColor = ""; // Reset background color

    // Continuous spinning animation
    const spinDuration = 4000; // Total spinning time
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
                    coinElement.innerHTML = result;
                    coinElement.style.backgroundColor =
                        result === "Heads" ? "#FFD700" : "#8A2BE2";

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
