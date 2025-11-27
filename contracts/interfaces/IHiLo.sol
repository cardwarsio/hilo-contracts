// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IHiLo {
    enum Suit {
        None, // No suit prediction
        Spades,
        Hearts,
        Diamonds,
        Clubs,
        Joker // Special Joker card (no suit, just Joker)
    }

    enum GuessType {
        Lower, // 0: Lower than current card
        Joker, // 1: Joker card
        Higher // 2: Higher than current card
    }

    struct HiLoStats {
        uint256 currentNumber;
        Suit currentSuit;
        uint256 streak;
        uint256 totalPlays;
        uint256 totalWins;
        uint256 superGemPoints;
        uint256 bestStreak;
    }

    function getUserStats(
        address user
    )
        external
        view
        returns (
            uint256 currentNumber,
            uint8 currentSuit,
            uint256 streak,
            uint256 totalPlays,
            uint256 totalWins,
            uint256 superGemPoints,
            uint256 bestStreak
        );

    function getPlayersByWinRate(
        uint256 minWinRate,
        uint256 limit
    )
        external
        view
        returns (
            address[] memory addresses,
            uint256[] memory totalWins,
            uint256[] memory totalPlays,
            uint256[] memory winRates
        );

    function getPlayersByStreak(
        uint256 minStreak,
        uint256 limit
    )
        external
        view
        returns (
            address[] memory addresses,
            uint256[] memory bestStreaks,
            uint256[] memory currentStreaks
        );

    function getPlayersBySuperGems(
        uint256 minSuperGems,
        uint256 limit
    )
        external
        view
        returns (
            address[] memory addresses,
            uint256[] memory superGemPoints
        );

    function getActivePlayers(
        uint256 hoursParam
    ) external view returns (address[] memory);

    function getPlayersWithMembership(
        uint8 tier
    ) external view returns (address[] memory);
}
