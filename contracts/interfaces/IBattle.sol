// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBattle {
    enum BattleStatus {
        Pending, // Waiting for opponent to accept
        Active, // Battle in progress
        Completed, // Battle finished
        Cancelled, // Battle cancelled
        Expired // Battle expired (timeout)
    }

    struct Battle {
        address challenger;
        address opponent;
        BattleStatus status;
        uint256 betAmount; // ETH bet amount
        uint256 startedAt;
        uint256 completedAt;
        uint256 lastMoveAt; // Last move timestamp
        address currentPlayer; // Who should play next
        address winner;
        uint256 challengerScore;
        uint256 opponentScore;
        uint256 rounds; // Number of rounds played
        uint256 currentCardNumber; // Current card number for this round (shared between players)
        uint8 currentCardSuit; // Current card suit for this round (shared between players)
        uint256 previousCardNumber; // Previous card number (for comparison)
        uint8 previousCardSuit; // Previous card suit
        bool challengerPlayed; // Has challenger played this round?
        bool opponentPlayed; // Has opponent played this round?
    }

    event BattleCreated(
        uint256 indexed battleId,
        address indexed challenger,
        address indexed opponent,
        uint256 betAmount,
        uint256 timestamp
    );

    event BattleStarted(
        uint256 indexed battleId,
        address indexed challenger,
        address indexed opponent,
        uint256 timestamp
    );

    event BattleRoundCompleted(
        uint256 indexed battleId,
        address indexed player,
        bool won,
        uint256 score,
        uint256 timestamp
    );

    event BattleCompleted(
        uint256 indexed battleId,
        address indexed winner,
        address indexed loser,
        uint256 reward,
        uint256 timestamp
    );

    event BattleCancelled(
        uint256 indexed battleId,
        address indexed cancelledBy,
        uint256 timestamp
    );

    event BattleInvitationSent(
        uint256 indexed battleId,
        address indexed from,
        address indexed to,
        uint256 timestamp
    );

    event BattleInvitationAccepted(
        uint256 indexed battleId,
        address indexed acceptedBy,
        uint256 timestamp
    );

    event BattleInvitationRejected(
        uint256 indexed battleId,
        address indexed rejectedBy,
        uint256 timestamp
    );

    event BattleExpired(
        uint256 indexed battleId,
        address indexed winner,
        address indexed loser,
        uint256 timestamp
    );

    event PlayerJoinedQueue(address indexed player, uint256 timestamp);

    event PlayerLeftQueue(address indexed player, uint256 timestamp);

    event BattleEmojiSent(
        uint256 indexed battleId,
        address indexed from,
        address indexed to,
        uint256 emojiItemId,
        uint256 timestamp
    );

    function getTopBattlePlayers(
        uint256 limit,
        uint8 sortBy
    )
        external
        view
        returns (
            address[] memory addresses,
            uint256[] memory wins,
            uint256[] memory losses,
            uint256[] memory winRates,
            uint256[] memory totalBattles
        );

    function getActiveBattlePlayers()
        external
        view
        returns (address[] memory);

    function getPlayersInQueueWithStats()
        external
        view
        returns (
            address[] memory addresses,
            uint256[] memory wins,
            uint256[] memory losses,
            uint256[] memory winRates,
            uint256[] memory totalBattles
        );

    function getPlayersByBattleWinRate(
        uint256 minWinRate,
        uint256 limit
    )
        external
        view
        returns (
            address[] memory addresses,
            uint256[] memory wins,
            uint256[] memory losses,
            uint256[] memory winRates
        );

    function getRecentBattlePlayers(
        uint256 hoursParam,
        uint256 limit
    ) external view returns (address[] memory);

    function getUserBattleStats(
        address user
    ) external view returns (uint256 wins, uint256 losses, uint256 totalBattles);
}
