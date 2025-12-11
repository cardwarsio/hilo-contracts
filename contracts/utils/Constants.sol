// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Constants {
    uint256 public constant MEMBERSHIP_DURATION = 30 days;
    uint256 public constant MAX_CARD_VALUE = 13; // K (King)
    uint256 public constant MIN_CARD_VALUE = 1; // A (Ace)
    uint256 public constant JOKER_CARD_VALUE = 0; // Special Joker card
    uint256 public constant SUIT_COUNT = 4;
    uint256 public constant CARDS_PER_SUIT = 13;
    uint256 public constant TOTAL_CARDS = 52; // 4 suits Ã— 13 cards
    uint256 public constant TOTAL_CARDS_WITH_JOKER = 53; // 52 normal cards + 1 Joker card

    uint256 public constant JOKER_BONUS_MULTIPLIER = 100; // 100x bonus for correct Joker prediction

    // Multipliers are stored as 10x (e.g., 15 = 1.5x, 20 = 2x, 30 = 3x)
    uint256 public constant MULTIPLIER_BASIC = 15; // 1.5x (15/10)
    uint256 public constant MULTIPLIER_PLUS = 20; // 2x (20/10)
    uint256 public constant MULTIPLIER_PRO = 30; // 3x (30/10)

    uint256 public constant BASE_SUPERGEM_WIN = 1;
    uint256 public constant BASE_SUPERGEM_SUIT_WIN = 5; // 5 SuperGems for correct suit prediction

    uint256 public constant SUIT_WRONG_PENALTY = 3; // SuperGems lost when suit prediction is wrong
    uint256 public constant HILO_WRONG_PENALTY = 1; // SuperGems lost when HiLo guess is wrong

    uint256 public constant STREAK_THRESHOLD_LOW = 5;
    uint256 public constant STREAK_THRESHOLD_HIGH = 10;

    uint256 public constant STREAK_BONUS_BASIC_LOW = 1; // Basic membership: 1 SuperGem bonus at streak 5+
    uint256 public constant STREAK_BONUS_BASIC_HIGH = 2; // Basic membership: 2 SuperGem bonus at streak 10+
    uint256 public constant STREAK_BONUS_PLUS_LOW = 1;
    uint256 public constant STREAK_BONUS_PLUS_HIGH = 3;
    uint256 public constant STREAK_BONUS_PRO_LOW = 2;
    uint256 public constant STREAK_BONUS_PRO_HIGH = 5;

    uint256 public constant TX_BOOST_BATCH_SIZE = 10;
    uint256 public constant BOOST_DURATION_1H = 1 hours;
    uint256 public constant BOOST_DURATION_4H = 4 hours;

    uint256 public constant EXTRA_CREDITS_AMOUNT = 100;
    uint256 public constant DAILY_FREE_GUESSES = 100; // Free guesses per day

    // Achievement milestones
    uint256 public constant ACHIEVEMENT_MILESTONE_5 = 5;
    uint256 public constant ACHIEVEMENT_MILESTONE_10 = 10;
    uint256 public constant ACHIEVEMENT_MILESTONE_20 = 20;

    // Achievement bonus rewards
    uint256 public constant ACHIEVEMENT_BONUS_5 = 5; // 5 SuperGems for 5 correct guesses
    uint256 public constant ACHIEVEMENT_BONUS_10 = 15; // 15 SuperGems for 10 correct guesses
    uint256 public constant ACHIEVEMENT_BONUS_20 = 50; // 50 SuperGems for 20 correct guesses

    // Clan creation fee
    uint256 public constant CLAN_CREATION_FEE = 0.00005 ether; // 0.00005 ETH to create a clan
}
