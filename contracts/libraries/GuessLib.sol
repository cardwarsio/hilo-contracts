// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../utils/Constants.sol";

library GuessLib {
    function evaluateGuess(
        uint8 guessType, // 0=Lower, 1=Joker, 2=Higher
        uint8 guessedSuit, // 0=None, 1-4=Suits, 5=Joker
        uint256 currentNumber,
        uint256 newNumber,
        uint8 newSuit
    ) internal pure returns (bool isWin, bool isJokerWin, bool isSuitWin) {
        isJokerWin = false;
        isSuitWin = false;

        // Special case: Same number (tie) - neither lower nor higher is valid
        // In this case, we treat it as a loss to maintain game integrity
        // The user should have predicted Joker if they expected the same number
        bool isTie = (newNumber != 0) && (newNumber == currentNumber);

        // Determine if guess is correct
        if (guessType == 0) {
            // Lower guess
            isWin = (newNumber != 0) && (newNumber < currentNumber) && !isTie;
        } else if (guessType == 1) {
            // Joker guess
            isJokerWin = (newNumber == 0);
            isWin = isJokerWin;
        } else if (guessType == 2) {
            // Higher guess
            isWin = (newNumber != 0) && (newNumber > currentNumber) && !isTie;
        }

        // Check if user made a suit prediction (only for normal cards, not Joker)
        isSuitWin =
            (guessedSuit != 0) &&
            (newNumber != 0) &&
            (guessedSuit == newSuit);
    }

    function applyJokerBonus(
        uint256 superGemEarned
    ) internal pure returns (uint256) {
        if (
            superGemEarned > type(uint256).max / Constants.JOKER_BONUS_MULTIPLIER
        ) {
            revert(); // Overflow protection
        }
        return superGemEarned * Constants.JOKER_BONUS_MULTIPLIER;
    }
}
