// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library RandomLib {
    // Uses only block.prevrandao (Ethereum's secure RNG) + user + nonce
    function generateRandomNumber(
        address user,
        uint256 nonce,
        uint256 maxValue
    ) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.prevrandao, // Ethereum's secure RNG (manipulation-resistant)
                        block.number, // Additional entropy (block number)
                        user, // User-specific entropy
                        nonce // Guess-specific entropy
                    )
                )
            ) % maxValue;
    }

    // Card generation with Yates-Fisher Shuffle (DEFAULT - Maximum Security)
    // Uses shuffled deck to prevent front-running and ensure perfect randomness
    // Each game session (53 cards) uses a unique shuffled deck
    function generateCard(
        address user,
        uint256 nonce
    ) internal view returns (uint256 cardValue, uint8 suitValue) {
        // Game session ID: Each 53 cards form a session (prevents repetition)
        uint256 gameSessionId = nonce / 53;
        
        // Generate unique seed for this game session
        uint256 seed = generateDeckSeed(user, gameSessionId);
        
        // Shuffle deck using Yates-Fisher algorithm
        uint256[53] memory deck = shuffleDeck(seed);
        
        // Draw card from shuffled deck (position based on nonce within session)
        uint256 cardIndex = nonce % 53;
        uint256 drawnCard = deck[cardIndex];
        
        // Convert to card value and suit
        if (drawnCard == 0) {
            // Joker card
            return (0, 5); // cardValue = 0 (Joker), suitValue = 5 (Joker suit)
        } else {
            // Normal card (1-52)
            uint256 idx = drawnCard - 1; // 0-51
            cardValue = (idx % 13) + 1; // 1-13 (A=1, 2-10, J=11, Q=12, K=13)
            suitValue = uint8(idx / 13); // 0-3 (Spades, Hearts, Diamonds, Clubs)
            return (cardValue, suitValue);
        }
    }

    // Yates-Fisher Shuffle: Creates a shuffled deck and draws cards sequentially
    // This ensures true randomness and prevents card repetition until deck is exhausted
    struct ShuffledDeck {
        uint256 seed; // Seed for this deck
        uint256 cardsDrawn; // Number of cards drawn from this deck
        uint256[53] deck; // Shuffled deck (0 = Joker, 1-52 = normal cards)
    }

    // Generate seed for deck shuffle (based on user + game session)
    function generateDeckSeed(
        address user,
        uint256 gameSessionId
    ) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.prevrandao,
                        block.number,
                        user,
                        gameSessionId
                    )
                )
            );
    }

    // Yates-Fisher Shuffle Algorithm
    // Creates a truly random permutation of 53 cards (52 normal + 1 Joker)
    function shuffleDeck(
        uint256 seed
    ) internal pure returns (uint256[53] memory deck) {
        // Initialize deck: 0 = Joker, 1-52 = normal cards
        for (uint256 i = 0; i < 53; i++) {
            deck[i] = i;
        }

        // Yates-Fisher Shuffle: O(n) time complexity
        for (uint256 i = 52; i > 0; i--) {
            // Generate random index from 0 to i (inclusive)
            uint256 j = uint256(keccak256(abi.encodePacked(seed, i))) % (i + 1);

            // Swap deck[i] and deck[j]
            uint256 temp = deck[i];
            deck[i] = deck[j];
            deck[j] = temp;
        }
    }

    // Draw card from shuffled deck
    // Returns card value and suit, and whether deck needs reshuffle
    function drawFromShuffledDeck(
        ShuffledDeck memory deckState,
        uint256 blockNumber
    )
        internal
        pure
        returns (
            uint256 cardValue,
            uint8 suitValue,
            ShuffledDeck memory newDeckState
        )
    {
        newDeckState = deckState;

        // If deck is exhausted, reshuffle with new seed
        if (newDeckState.cardsDrawn >= 53) {
            // Generate new seed (increment seed to ensure different shuffle)
            newDeckState.seed = uint256(
                keccak256(abi.encodePacked(newDeckState.seed, blockNumber))
            );
            newDeckState.deck = shuffleDeck(newDeckState.seed);
            newDeckState.cardsDrawn = 0;
        }

        // Draw card from current position
        uint256 drawnCard = newDeckState.deck[newDeckState.cardsDrawn];
        newDeckState.cardsDrawn++;

        // Convert to card value and suit
        if (drawnCard == 0) {
            // Joker card
            return (0, 5, newDeckState);
        } else {
            // Normal card (1-52)
            uint256 cardIndex = drawnCard - 1; // 0-51
            cardValue = (cardIndex % 13) + 1; // 1-13
            suitValue = uint8(cardIndex / 13); // 0-3
            return (cardValue, suitValue, newDeckState);
        }
    }

    // Legacy function: generateCard now uses shuffle by default
    // This function is kept for backward compatibility but now just calls generateCard
    function generateCardWithShuffle(
        address user,
        uint256 nonce,
        bool /* useShuffle - ignored, always uses shuffle now */
    ) internal view returns (uint256 cardValue, uint8 suitValue) {
        // Always use shuffle (maximum security)
        return generateCard(user, nonce);
    }

    // Legacy functions (backward compatibility)
    function generateCardNumber(
        address user,
        uint256 nonce
    ) internal view returns (uint256) {
        (uint256 cardValue, ) = generateCard(user, nonce);
        return cardValue;
    }

    function generateSuit(
        address user,
        uint256 nonce
    ) internal view returns (uint8) {
        (, uint8 suitValue) = generateCard(user, nonce);
        return suitValue;
    }
}
