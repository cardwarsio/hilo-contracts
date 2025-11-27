// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LeaderboardLib {
    uint256 public constant WEEK_DURATION = 7 days;

    struct WeeklyLeaderboard {
        address topPlayer;
        uint256 topPlayerScore;
        uint256 topClanId;
        uint256 topClanScore;
        uint256 weekStartTime;
        uint256 weekEndTime;
    }

    function shouldReset(
        uint256 currentWeekStart,
        uint256 timestamp
    ) internal pure returns (bool) {
        return timestamp >= currentWeekStart + WEEK_DURATION;
    }

    function updatePlayerScore(
        mapping(address => uint256) storage weeklyPlayerScores,
        address player,
        uint256 superGemsEarned
    ) internal {
        weeklyPlayerScores[player] += superGemsEarned;
    }

    function isNewTopPlayer(
        uint256 playerScore,
        uint256 currentTopScore
    ) internal pure returns (bool) {
        return playerScore > currentTopScore;
    }

    function isNewTopClan(
        uint256 clanScore,
        uint256 currentTopScore
    ) internal pure returns (bool) {
        return clanScore > currentTopScore;
    }
}


