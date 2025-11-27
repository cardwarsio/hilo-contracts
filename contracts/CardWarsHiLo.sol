// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/IMarketplace.sol";
import "./interfaces/IHiLo.sol";
import "./interfaces/IBoost.sol";
import "./interfaces/ITrackable.sol";
import "./interfaces/IBattle.sol";
import "./interfaces/IClan.sol";
import "./libraries/MembershipLib.sol";
import "./libraries/RandomLib.sol";
import "./libraries/CEILib.sol";
import "./libraries/EventLib.sol";
import "./libraries/AchievementLib.sol";
import "./libraries/LeaderboardLib.sol";
import "./libraries/GuessLib.sol";
import "./utils/Errors.sol";
import "./utils/Constants.sol";
import "./CardWarsMarketplace.sol";

contract CardWarsHiLo is
    IHiLo,
    ITrackable,
    ReentrancyGuard,
    Pausable,
    Ownable,
    AccessControl
{
    using MembershipLib for IMarketplace;
    using RandomLib for address;
    using CEILib for CEILib.CEIContext;
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    receive() external payable {
        revert("Direct ETH transfers not allowed");
    }

    fallback() external payable {
        revert("Function not found");
    }

    IMarketplace public marketplace;
    IBattle public battleContract;
    IClan public clanContract;
    mapping(address => HiLoStats) public stats;

    address[] public players;
    mapping(address => bool) public isPlayer;
    mapping(address => uint256) public playerIndex;

    mapping(address => bytes32[]) public userEventIds;
    mapping(bytes32 => ITrackable.TrackedEvent) public trackedEvents;
    mapping(address => uint256) public userEventCounts;

    uint256 public totalGamesStarted;
    uint256 public totalGuesses;
    mapping(address => uint256) public userGameStartCount;
    mapping(address => uint256) public userGuessCount;

    // Achievement tracking (consecutive correct guesses)
    mapping(address => uint256) public consecutiveCorrectGuesses; // Consecutive correct guesses in a row
    mapping(address => uint256) public lastAchievementMilestone; // Last milestone reached (5, 10, 20)

    // Daily guess limit tracking
    mapping(address => uint256) public dailyGuessCount; // Daily guess count per user
    mapping(address => uint256) public lastGuessDay; // Last day user made a guess (timestamp / 1 day)

    // Reset game hourly limit tracking
    mapping(address => uint256) public resetCountThisHour; // Reset count in current hour
    mapping(address => uint256) public lastResetHour; // Last hour user reset game (timestamp / 1 hour)

    // Weekly Leaderboard System
    uint256 public currentWeekStart;

    struct WeeklyLeaderboard {
        address topPlayer; // Player with most SuperGems earned this week
        uint256 topPlayerScore; // SuperGems earned by top player this week
        uint256 topClanId; // Clan with most battle score this week
        uint256 topClanScore; // Battle score of top clan this week
        uint256 weekStartTime;
        uint256 weekEndTime;
    }

    mapping(uint256 => WeeklyLeaderboard) public weeklyLeaderboards; // weekNumber => leaderboard
    mapping(address => uint256) public weeklyPlayerScores; // player => SuperGems earned this week
    mapping(uint256 => uint256) public weeklyClanScores; // clanId => battle score this week
    uint256 public currentWeekNumber;

    event GameStarted(
        address indexed user,
        uint256 indexed timestamp,
        uint256 startingNumber,
        Suit startingSuit
    );

    event GuessResult(
        address indexed user,
        uint256 indexed timestamp,
        bool higher,
        Suit guessedSuit,
        uint256 newNumber,
        Suit newSuit,
        bool isWin,
        bool isSuitWin,
        uint256 streak,
        uint256 superGemEarned,
        uint256 totalPlays,
        uint256 totalWins,
        uint256 totalSuperGems,
        uint256 bestStreak
    );

    event JokerCardDrawn(
        address indexed user,
        uint256 indexed timestamp,
        uint256 bonusMultiplier
    );

    event TieResult(
        address indexed user,
        uint256 currentNumber,
        uint256 newNumber,
        uint256 timestamp
    );

    event BatchGuessResult(
        address indexed user,
        uint256 indexed timestamp,
        uint256 batchSize,
        uint256 totalWins,
        uint256 totalSuperGems,
        uint256 finalStreak,
        uint256 totalPlays,
        uint256 totalWinsAfter,
        uint256 totalSuperGemsAfter,
        uint256 bestStreakAfter
    );

    event StatsUpdated(
        address indexed user,
        uint256 indexed timestamp,
        uint256 totalPlays,
        uint256 totalWins,
        uint256 superGemPoints,
        uint256 bestStreak,
        uint256 currentStreak,
        uint256 winRate
    );

    event BestStreakUpdated(
        address indexed user,
        uint256 indexed timestamp,
        uint256 oldBestStreak,
        uint256 newBestStreak
    );

    event PlayerRegistered(
        address indexed user,
        uint256 indexed timestamp,
        uint256 playerIndex
    );

    event StreakBroken(
        address indexed user,
        uint256 indexed timestamp,
        uint256 brokenStreak
    );

    event MarketplaceUpdated(
        address indexed oldMarketplace,
        address indexed newMarketplace,
        uint256 indexed timestamp
    );

    event GameReset(
        address indexed user,
        uint256 indexed timestamp,
        uint256 previousNumber,
        Suit previousSuit
    );

    event AchievementUnlocked(
        address indexed user,
        uint256 indexed milestone,
        uint256 bonusReward,
        uint256 totalCorrectGuesses,
        uint256 indexed timestamp
    );

    event BattleContractUpdated(
        address indexed oldBattleContract,
        address indexed newBattleContract,
        uint256 indexed timestamp
    );

    event ClanContractUpdated(
        address indexed oldClanContract,
        address indexed newClanContract,
        uint256 indexed timestamp
    );

    event WeeklyLeaderboardReset(
        uint256 indexed weekNumber,
        address indexed topPlayer,
        uint256 topPlayerScore,
        uint256 indexed topClanId,
        uint256 topClanScore,
        uint256 timestamp
    );

    event WeeklyLeaderboardUpdated(
        uint256 indexed weekNumber,
        address indexed topPlayer,
        uint256 topPlayerScore,
        uint256 indexed topClanId,
        uint256 topClanScore,
        uint256 timestamp
    );

    constructor(address _marketplace) Ownable(msg.sender) {
        // Allow zero address in constructor - will be set later via setMarketplace
        if (_marketplace != address(0)) {
            marketplace = IMarketplace(_marketplace);
        }
        currentWeekStart = block.timestamp;
        currentWeekNumber = 1;
        weeklyLeaderboards[currentWeekNumber] = WeeklyLeaderboard({
            topPlayer: address(0),
            topPlayerScore: 0,
            topClanId: 0,
            topClanScore: 0,
            weekStartTime: currentWeekStart,
            weekEndTime: currentWeekStart + LeaderboardLib.WEEK_DURATION
        });
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
        _pause(); // Start paused for safety
    }

    function setMarketplace(address _marketplace) external onlyOwner {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (
            address(marketplace) != address(0) &&
            msg.sender != address(marketplace)
        ) {
            revert Unauthorized();
        }
        if (_marketplace == address(0)) {
            revert InvalidAddress();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        address oldMarketplace = address(marketplace);
        marketplace = IMarketplace(_marketplace);
        ctx.completeEffects();

        ctx.requireInteractions();
        emit MarketplaceUpdated(oldMarketplace, _marketplace, block.timestamp);
        _trackEvent(
            msg.sender,
            "MarketplaceUpdated",
            abi.encode(oldMarketplace, _marketplace)
        );
    }

    function setBattleContract(address _battleContract) external onlyOwner {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (_battleContract == address(0)) {
            revert InvalidAddress();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        address oldBattleContract = address(battleContract);
        battleContract = IBattle(_battleContract);
        ctx.completeEffects();

        ctx.requireInteractions();
        emit BattleContractUpdated(
            oldBattleContract,
            _battleContract,
            block.timestamp
        );
        _trackEvent(
            msg.sender,
            "BattleContractUpdated",
            abi.encode(oldBattleContract, _battleContract)
        );
    }

    function setClanContract(address _clanContract) external onlyOwner {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (_clanContract == address(0)) {
            revert InvalidAddress();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        address oldClanContract = address(clanContract);
        clanContract = IClan(_clanContract);
        ctx.completeEffects();

        ctx.requireInteractions();
        emit ClanContractUpdated(
            oldClanContract,
            _clanContract,
            block.timestamp
        );
        _trackEvent(
            msg.sender,
            "ClanContractUpdated",
            abi.encode(oldClanContract, _clanContract)
        );
    }

    function startGame() external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        HiLoStats storage userStats = stats[msg.sender];

        ctx.requireChecks();
        if (userStats.currentNumber != 0) {
            revert GameAlreadyStarted();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        (uint256 randomNumber, uint8 randomSuitRaw) = msg.sender.generateCard(
            0
        );
        Suit randomSuit;
        if (randomNumber == 0) {
            randomSuit = Suit.Joker;
        } else {
            randomSuit = Suit(randomSuitRaw + 1); // +1 because Suit.None = 0
        }

        userStats.currentNumber = randomNumber;
        userStats.currentSuit = randomSuit;
        userStats.streak = 0;

        bool isNewPlayer = !isPlayer[msg.sender];
        if (isNewPlayer) {
            isPlayer[msg.sender] = true;
            playerIndex[msg.sender] = players.length;
            players.push(msg.sender);
        }

        unchecked {
            totalGamesStarted++;
            userGameStartCount[msg.sender]++;
        }
        ctx.completeEffects();

        ctx.requireInteractions();
        emit GameStarted(msg.sender, block.timestamp, randomNumber, randomSuit);
        if (isNewPlayer) {
            emit PlayerRegistered(
                msg.sender,
                block.timestamp,
                playerIndex[msg.sender]
            );
        }
        _trackEvent(
            msg.sender,
            "GameStarted",
            abi.encode(randomNumber, uint8(randomSuit))
        );
    }

    function _checkAchievements(address user) internal returns (uint256) {
        uint256 consecutive = consecutiveCorrectGuesses[user];
        uint256 lastMilestone = lastAchievementMilestone[user];

        AchievementLib.AchievementResult memory result = AchievementLib
            .checkAchievements(consecutive, lastMilestone);

        if (result.bonus > 0) {
            lastAchievementMilestone[user] = result.newMilestone;
            emit AchievementUnlocked(
                user,
                result.newMilestone,
                result.bonus,
                consecutive,
                block.timestamp
            );
        }

        return result.bonus;
    }

    function _checkAndConsumeCredit(address user) internal {
        uint256 currentDay = block.timestamp / 1 days;

        // Reset daily count if it's a new day
        if (lastGuessDay[user] != currentDay) {
            dailyGuessCount[user] = 0;
            lastGuessDay[user] = currentDay;
        }

        // Check if user has free daily guesses remaining
        if (dailyGuessCount[user] < Constants.DAILY_FREE_GUESSES) {
            dailyGuessCount[user]++;
            return; // Free guess, no credit needed
        }

        // Daily limit exceeded, try to consume extra credits
        CardWarsMarketplace marketplaceContract = CardWarsMarketplace(
            payable(address(marketplace))
        );
        bool consumed = marketplaceContract.consumeExtraCredits(user, 1);
        if (!consumed) {
            revert InsufficientCredits();
        }
    }

    function _checkAndConsumeBurnIt(address user) internal returns (bool) {
        CardWarsMarketplace marketplaceContract = CardWarsMarketplace(
            payable(address(marketplace))
        );
        return marketplaceContract.consumeBurnIt(user, 1);
    }

    function _checkAndResetWeeklyLeaderboard() internal {
        if (LeaderboardLib.shouldReset(currentWeekStart, block.timestamp)) {
            WeeklyLeaderboard storage currentLeaderboard = weeklyLeaderboards[
                currentWeekNumber
            ];

            emit WeeklyLeaderboardReset(
                currentWeekNumber,
                currentLeaderboard.topPlayer,
                currentLeaderboard.topPlayerScore,
                currentLeaderboard.topClanId,
                currentLeaderboard.topClanScore,
                block.timestamp
            );

            currentWeekNumber++;
            currentWeekStart = block.timestamp;

            weeklyLeaderboards[currentWeekNumber] = WeeklyLeaderboard({
                topPlayer: address(0),
                topPlayerScore: 0,
                topClanId: 0,
                topClanScore: 0,
                weekStartTime: currentWeekStart,
                weekEndTime: currentWeekStart + LeaderboardLib.WEEK_DURATION
            });
        }
    }

    function _updateWeeklyPlayerLeaderboard(
        address player,
        uint256 superGemsEarned
    ) internal {
        _checkAndResetWeeklyLeaderboard();

        LeaderboardLib.updatePlayerScore(
            weeklyPlayerScores,
            player,
            superGemsEarned
        );
        WeeklyLeaderboard storage currentLeaderboard = weeklyLeaderboards[
            currentWeekNumber
        ];

        if (
            LeaderboardLib.isNewTopPlayer(
                weeklyPlayerScores[player],
                currentLeaderboard.topPlayerScore
            )
        ) {
            currentLeaderboard.topPlayer = player;
            currentLeaderboard.topPlayerScore = weeklyPlayerScores[player];

            _updateWeeklyLeaderboardEvent();
        }
    }

    function _updateWeeklyClanLeaderboard() internal {
        if (address(clanContract) == address(0)) {
            return;
        }

        _checkAndResetWeeklyLeaderboard();

        try clanContract.getTopClans(1) returns (IClan.Clan[] memory topClans) {
            if (topClans.length > 0 && topClans[0].clanId > 0) {
                uint256 currentClanBattleScore = topClans[0].battleScore;
                WeeklyLeaderboard
                    storage currentLeaderboard = weeklyLeaderboards[
                        currentWeekNumber
                    ];

                if (
                    LeaderboardLib.isNewTopClan(
                        currentClanBattleScore,
                        currentLeaderboard.topClanScore
                    )
                ) {
                    currentLeaderboard.topClanId = topClans[0].clanId;
                    currentLeaderboard.topClanScore = currentClanBattleScore;

                    _updateWeeklyLeaderboardEvent();
                }
            }
        } catch {
            // Ignore errors from clan contract
        }
    }

    function _updateWeeklyLeaderboardEvent() internal {
        WeeklyLeaderboard storage currentLeaderboard = weeklyLeaderboards[
            currentWeekNumber
        ];
        emit WeeklyLeaderboardUpdated(
            currentWeekNumber,
            currentLeaderboard.topPlayer,
            currentLeaderboard.topPlayerScore,
            currentLeaderboard.topClanId,
            currentLeaderboard.topClanScore,
            block.timestamp
        );
    }

    function guess(
        uint8 guessType, // 0=Lower, 1=Joker, 2=Higher
        Suit guessedSuit,
        bool useBurnIt // Manual Burn It usage
    ) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        HiLoStats storage userStats = stats[msg.sender];

        ctx.requireChecks();
        if (userStats.currentNumber == 0) {
            revert GameNotStarted();
        }
        if (guessType > 2) {
            revert InvalidGuessType();
        }

        // Handle Burn It usage (manual)
        if (useBurnIt) {
            // Check and consume Burn It credit
            CardWarsMarketplace marketplaceContract = CardWarsMarketplace(
                payable(address(marketplace))
            );
            if (!marketplaceContract.consumeBurnIt(msg.sender, 1)) {
                revert InsufficientCredits(); // User doesn't have Burn It credits
            }
        } else {
            _checkAndConsumeCredit(msg.sender);
        }
        ctx.completeChecks();

        ctx.requireEffects();
        uint256 currentNumber = userStats.currentNumber;

        bool isWin = false;
        bool isJokerWin = false;
        bool isSuitWin = false;
        uint256 newNumber = 0;
        Suit newSuit = Suit.None;

        if (useBurnIt) {
            // Burn It: Skip card generation, auto correct guess
            isWin = true;
            // Generate a dummy card for display purposes (but it's auto-correct)
            uint256 dummyNumber;
            uint8 dummySuitRaw;
            (dummyNumber, dummySuitRaw) = msg.sender.generateCard(
                userStats.totalPlays
            );
            newNumber = dummyNumber;
            if (newNumber == 0) {
                newSuit = Suit.Joker;
                isJokerWin = true;
            } else {
                newSuit = Suit(dummySuitRaw + 1);
            }
            // Auto-correct suit prediction if made
            if (guessedSuit != Suit.None) {
                isSuitWin = (guessedSuit == newSuit);
            }
        } else {
            // Normal guess flow
            // Generate new card (can be Joker or normal card)
            uint8 newSuitRaw;
            (newNumber, newSuitRaw) = msg.sender.generateCard(
                userStats.totalPlays
            );

            if (newNumber == 0) {
                // Joker card
                newSuit = Suit.Joker;
            } else {
                // Normal card
                newSuit = Suit(newSuitRaw + 1); // +1 because Suit.None = 0
            }

            // Determine if guess is correct using GuessLib
            (isWin, isJokerWin, isSuitWin) = GuessLib.evaluateGuess(
                guessType,
                uint8(guessedSuit),
                currentNumber,
                newNumber,
                uint8(newSuit)
            );
        }

        uint256 oldBestStreak = userStats.bestStreak;
        uint256 oldStreak = userStats.streak;

        userStats.totalPlays++;
        uint256 superGemEarned = 0;
        uint256 achievementBonus = 0;

        bool madeSuitPrediction = (guessedSuit != Suit.None);

        if (isWin) {
            // Increment consecutive correct guesses for achievements (in a row)
            consecutiveCorrectGuesses[msg.sender]++;

            // Check for achievement milestones (5, 10, 20 in a row)
            achievementBonus = _checkAchievements(msg.sender);

            // If user made suit prediction and it's wrong, streak breaks and lose 3 SuperGems
            if (madeSuitPrediction && !isSuitWin) {
                superGemEarned = 0;
                // Streak breaks when suit prediction is wrong
                uint256 suitOldStreak = userStats.streak;
                consecutiveCorrectGuesses[msg.sender] = 0;

                // Check for streak protection
                CardWarsMarketplace marketplaceContractSuit = CardWarsMarketplace(
                        payable(address(marketplace))
                    );
                bool hasProtection = marketplaceContractSuit.streakProtection(
                    msg.sender
                );

                if (hasProtection) {
                    // Streak protection active - don't break streak, consume protection
                    marketplaceContractSuit.consumeStreakProtection(msg.sender);
                } else if (userStats.streak > 0) {
                    emit StreakBroken(
                        msg.sender,
                        block.timestamp,
                        suitOldStreak
                    );
                    userStats.streak = 0;
                }

                // Deduct 3 SuperGems for wrong suit prediction
                uint256 penalty = Constants.SUIT_WRONG_PENALTY;
                if (userStats.superGemPoints >= penalty) {
                    userStats.superGemPoints -= penalty;
                } else {
                    // If user doesn't have enough SuperGems, set to 0
                    userStats.superGemPoints = 0;
                }

                // Still count as a win for totalWins
                userStats.totalWins++;
            } else {
                // Normal win or correct suit prediction
                userStats.streak++;
                userStats.totalWins++;

                uint256 multiplier = MembershipLib.getMultiplier(
                    marketplace,
                    msg.sender
                );
                uint256 streakBonus = MembershipLib.getStreakBonus(
                    marketplace,
                    msg.sender,
                    userStats.streak
                );
                superGemEarned = MembershipLib.calculateSuperGems(
                    isSuitWin,
                    multiplier,
                    streakBonus
                );

                // Apply 100x bonus for correct Joker prediction
                if (isJokerWin) {
                    superGemEarned = GuessLib.applyJokerBonus(superGemEarned);
                }

                userStats.superGemPoints += superGemEarned;

                // Add achievement bonus
                if (achievementBonus > 0) {
                    userStats.superGemPoints += achievementBonus;
                }

                // Update weekly leaderboard for player
                _updateWeeklyPlayerLeaderboard(
                    msg.sender,
                    superGemEarned + achievementBonus
                );

                if (userStats.streak > userStats.bestStreak) {
                    userStats.bestStreak = userStats.streak;
                }
            }
        } else {
            // Hi-Lo guess was wrong - check if it's a tie (same number)
            bool isTie = (newNumber != 0) && (newNumber == currentNumber);

            if (isTie) {
                // Tie: Same number appeared - streak doesn't break, but lose 1 SuperGem
                // Emit tie event
                emit TieResult(
                    msg.sender,
                    currentNumber,
                    newNumber,
                    block.timestamp
                );

                // Deduct 1 SuperGem for tie (wrong guess)
                uint256 penalty = Constants.HILO_WRONG_PENALTY;
                if (userStats.superGemPoints >= penalty) {
                    userStats.superGemPoints -= penalty;
                } else {
                    // If user doesn't have enough SuperGems, set to 0
                    userStats.superGemPoints = 0;
                }
            } else {
                // Hi-Lo guess was wrong (not a tie) - check for streak protection
                uint256 hiloOldStreak = userStats.streak;
                consecutiveCorrectGuesses[msg.sender] = 0;
                CardWarsMarketplace marketplaceContractGuess = CardWarsMarketplace(
                        payable(address(marketplace))
                    );
                bool hasProtection = marketplaceContractGuess.streakProtection(
                    msg.sender
                );

                if (hasProtection) {
                    // Streak protection active - don't break streak, consume protection
                    marketplaceContractGuess.consumeStreakProtection(
                        msg.sender
                    );
                } else if (userStats.streak > 0) {
                    emit StreakBroken(
                        msg.sender,
                        block.timestamp,
                        hiloOldStreak
                    );
                    userStats.streak = 0;
                }

                // Deduct 1 SuperGem for wrong HiLo guess
                uint256 penalty = Constants.HILO_WRONG_PENALTY;
                if (userStats.superGemPoints >= penalty) {
                    userStats.superGemPoints -= penalty;
                } else {
                    // If user doesn't have enough SuperGems, set to 0
                    userStats.superGemPoints = 0;
                }
            }
        }

        userStats.currentNumber = newNumber;
        userStats.currentSuit = newSuit;

        // Emit Joker card event if Joker was drawn
        if (newNumber == 0) {
            emit JokerCardDrawn(
                msg.sender,
                block.timestamp,
                isJokerWin ? Constants.JOKER_BONUS_MULTIPLIER : 0
            );
        }

        unchecked {
            totalGuesses++;
            userGuessCount[msg.sender]++;
        }
        ctx.completeEffects();

        ctx.requireInteractions();
        uint256 winRate = userStats.totalPlays > 0
            ? (userStats.totalWins * 100) / userStats.totalPlays
            : 0;

        if (oldBestStreak < userStats.bestStreak) {
            emit BestStreakUpdated(
                msg.sender,
                block.timestamp,
                oldBestStreak,
                userStats.bestStreak
            );
        }

        if (!isWin && oldStreak > 0) {
            emit StreakBroken(msg.sender, block.timestamp, oldStreak);
        }

        emit GuessResult(
            msg.sender,
            block.timestamp,
            guessType == 2, // higher (for backward compatibility)
            guessedSuit,
            newNumber,
            newSuit,
            isWin,
            isSuitWin,
            userStats.streak,
            superGemEarned + achievementBonus,
            userStats.totalPlays,
            userStats.totalWins,
            userStats.superGemPoints,
            userStats.bestStreak
        );

        emit StatsUpdated(
            msg.sender,
            block.timestamp,
            userStats.totalPlays,
            userStats.totalWins,
            userStats.superGemPoints,
            userStats.bestStreak,
            userStats.streak,
            winRate
        );

        _trackEvent(
            msg.sender,
            "GuessResult",
            abi.encode(
                guessType,
                uint8(guessedSuit),
                newNumber,
                uint8(newSuit),
                isWin,
                isSuitWin,
                isJokerWin
            )
        );
    }

    function batchGuess(
        uint8[] memory guessTypes, // 0=Lower, 1=Joker, 2=Higher
        Suit[] memory guessedSuits,
        bool useBurnIt // Manual Burn It usage for all guesses in batch
    ) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (
            guessTypes.length != guessedSuits.length || guessTypes.length == 0
        ) {
            revert InvalidBatchSize();
        }

        // Validate guess types
        for (uint256 i = 0; i < guessTypes.length; i++) {
            if (guessTypes[i] > 2) {
                revert InvalidGuessType();
            }
        }

        IBoost boostContract = IBoost(address(marketplace));
        IBoost.ActiveBoost memory boost = boostContract.getUserBoost(
            msg.sender
        );

        if (boost.boostType != IBoost.BoostType.TxBoost) {
            revert BoostNotActive();
        }

        if (boost.expiresAt < block.timestamp) {
            revert BoostExpired();
        }

        if (boost.remainingUses < guessTypes.length) {
            revert NoRemainingUses();
        }

        HiLoStats storage userStats = stats[msg.sender];

        if (userStats.currentNumber == 0) {
            revert GameNotStarted();
        }

        // Check daily free guesses and calculate required extra credits
        uint256 currentDay = block.timestamp / 1 days;
        uint256 remainingFreeGuesses = 0;

        // Reset daily count if it's a new day
        if (lastGuessDay[msg.sender] != currentDay) {
            dailyGuessCount[msg.sender] = 0;
            lastGuessDay[msg.sender] = currentDay;
        }

        // Calculate remaining free guesses
        if (dailyGuessCount[msg.sender] < Constants.DAILY_FREE_GUESSES) {
            remainingFreeGuesses =
                Constants.DAILY_FREE_GUESSES -
                dailyGuessCount[msg.sender];
        }

        // Handle Burn It usage (only for first guess in batch if enabled)
        uint256 effectiveBatchSize = guessTypes.length;
        if (useBurnIt) {
            // Check and consume Burn It credit for first guess
            CardWarsMarketplace marketplaceContract = CardWarsMarketplace(
                payable(address(marketplace))
            );
            if (!marketplaceContract.consumeBurnIt(msg.sender, 1)) {
                revert InsufficientCredits(); // User doesn't have Burn It credits
            }
            effectiveBatchSize -= 1; // First guess uses Burn It, reduce batch size for credit calculation
        }

        // Calculate how many extra credits are needed (excluding Burn It guess)
        uint256 requiredCredits = 0;
        if (effectiveBatchSize > remainingFreeGuesses) {
            requiredCredits = effectiveBatchSize - remainingFreeGuesses;
        }

        // Check if user has enough extra credits if needed
        if (requiredCredits > 0) {
            uint256 userCredits = marketplace.getUserExtraCredits(msg.sender);
            if (userCredits < requiredCredits) {
                revert InsufficientCredits();
            }
        }

        ctx.completeChecks();

        ctx.requireEffects();
        uint256 oldBestStreak = userStats.bestStreak;
        uint256 totalWins = 0;
        uint256 totalSuperGems = 0;
        uint256 currentNumber = userStats.currentNumber;
        Suit currentSuit = userStats.currentSuit;

        for (uint256 i = 0; i < guessTypes.length; i++) {
            // Generate new card (can be Joker or normal card)
            (uint256 newNumber, uint8 newSuitRaw) = msg.sender.generateCard(
                userStats.totalPlays + i
            );
            Suit newSuit;

            if (newNumber == 0) {
                // Joker card
                newSuit = Suit.Joker;
            } else {
                // Normal card
                newSuit = Suit(newSuitRaw + 1); // +1 because Suit.None = 0
            }

            // Determine if guess is correct using GuessLib
            bool madeSuitPrediction = (guessedSuits[i] != Suit.None);
            bool isWin;
            bool isJokerWin;
            bool isSuitWin;

            if (useBurnIt && i == 0) {
                // First guess uses Burn It: auto-correct
                isWin = true;
                isJokerWin = (newNumber == 0);
                // Auto-correct suit prediction if made
                isSuitWin = madeSuitPrediction
                    ? (guessedSuits[i] == newSuit)
                    : false;
            } else {
                // Normal guess evaluation
                (isWin, isJokerWin, isSuitWin) = GuessLib.evaluateGuess(
                    guessTypes[i],
                    uint8(guessedSuits[i]),
                    currentNumber,
                    newNumber,
                    uint8(newSuit)
                );
            }

            userStats.totalPlays++;
            uint256 superGemEarned = 0;
            uint256 achievementBonus = 0;

            if (isWin) {
                // Increment consecutive correct guesses for achievements (in a row)
                consecutiveCorrectGuesses[msg.sender]++;

                // Check for achievement milestones (5, 10, 20 in a row)
                achievementBonus = _checkAchievements(msg.sender);

                // If user made suit prediction and it's wrong, streak breaks and lose 3 SuperGems
                if (madeSuitPrediction && !isSuitWin) {
                    superGemEarned = 0;
                    // Streak breaks when suit prediction is wrong
                    uint256 batchSuitOldStreak = userStats.streak;
                    consecutiveCorrectGuesses[msg.sender] = 0;

                    // Check for streak protection
                    IMarketplace marketplaceInterface = marketplace;
                    bool hasProtection = CardWarsMarketplace(
                        payable(address(marketplaceInterface))
                    ).streakProtection(msg.sender);

                    if (hasProtection) {
                        // Streak protection active - don't break streak, consume protection
                        CardWarsMarketplace(
                            payable(address(marketplaceInterface))
                        ).consumeStreakProtection(msg.sender);
                    } else if (userStats.streak > 0) {
                        emit StreakBroken(
                            msg.sender,
                            block.timestamp,
                            batchSuitOldStreak
                        );
                        userStats.streak = 0;
                    }

                    // Deduct 3 SuperGems for wrong suit prediction
                    uint256 penalty = Constants.SUIT_WRONG_PENALTY;
                    if (userStats.superGemPoints >= penalty) {
                        userStats.superGemPoints -= penalty;
                        totalSuperGems -= penalty;
                    } else {
                        // If user doesn't have enough SuperGems, set to 0
                        uint256 lostAmount = userStats.superGemPoints;
                        userStats.superGemPoints = 0;
                        totalSuperGems -= lostAmount;
                    }

                    // Still count as a win for totalWins
                    userStats.totalWins++;
                    totalWins++;
                } else {
                    // Normal win or correct suit prediction
                    userStats.streak++;
                    userStats.totalWins++;
                    totalWins++;

                    uint256 multiplier = MembershipLib.getMultiplier(
                        marketplace,
                        msg.sender
                    );
                    uint256 streakBonus = MembershipLib.getStreakBonus(
                        marketplace,
                        msg.sender,
                        userStats.streak
                    );
                    superGemEarned = MembershipLib.calculateSuperGems(
                        isSuitWin,
                        multiplier,
                        streakBonus
                    );

                    // Apply 100x bonus for correct Joker prediction
                    if (isJokerWin) {
                        superGemEarned = GuessLib.applyJokerBonus(
                            superGemEarned
                        );
                    }

                    totalSuperGems += superGemEarned;
                    userStats.superGemPoints += superGemEarned;

                    // Add achievement bonus
                    if (achievementBonus > 0) {
                        totalSuperGems += achievementBonus;
                        userStats.superGemPoints += achievementBonus;
                    }

                    if (userStats.streak > userStats.bestStreak) {
                        userStats.bestStreak = userStats.streak;
                    }
                }
            } else {
                // Hi-Lo guess was wrong - check if it's a tie (same number)
                bool isTie = (newNumber != 0) && (newNumber == currentNumber);

                if (isTie) {
                    // Tie: Same number appeared - streak doesn't break, but lose 1 SuperGem
                    // Emit tie event
                    emit TieResult(
                        msg.sender,
                        currentNumber,
                        newNumber,
                        block.timestamp
                    );

                    // Deduct 1 SuperGem for tie (wrong guess)
                    uint256 penalty = Constants.HILO_WRONG_PENALTY;
                    if (userStats.superGemPoints >= penalty) {
                        userStats.superGemPoints -= penalty;
                        totalSuperGems -= penalty;
                    } else {
                        // If user doesn't have enough SuperGems, set to 0
                        uint256 lostAmount = userStats.superGemPoints;
                        userStats.superGemPoints = 0;
                        totalSuperGems -= lostAmount;
                    }
                } else {
                    // Hi-Lo guess was wrong (not a tie) - check for streak protection
                    uint256 batchHiloOldStreak = userStats.streak;
                    consecutiveCorrectGuesses[msg.sender] = 0;
                    IMarketplace marketplaceInterface = marketplace;
                    bool hasProtection = CardWarsMarketplace(
                        payable(address(marketplaceInterface))
                    ).streakProtection(msg.sender);

                    if (hasProtection) {
                        // Streak protection active - don't break streak, consume protection
                        CardWarsMarketplace(
                            payable(address(marketplaceInterface))
                        ).consumeStreakProtection(msg.sender);
                    } else if (userStats.streak > 0) {
                        emit StreakBroken(
                            msg.sender,
                            block.timestamp,
                            batchHiloOldStreak
                        );
                        userStats.streak = 0;
                    }

                    // Deduct 1 SuperGem for wrong HiLo guess
                    uint256 penalty = Constants.HILO_WRONG_PENALTY;
                    if (userStats.superGemPoints >= penalty) {
                        userStats.superGemPoints -= penalty;
                        totalSuperGems -= penalty;
                    } else {
                        // If user doesn't have enough SuperGems, set to 0
                        uint256 lostAmount = userStats.superGemPoints;
                        userStats.superGemPoints = 0;
                        totalSuperGems -= lostAmount;
                    }
                }
            }

            currentNumber = newNumber;
            currentSuit = newSuit;

            emit GuessResult(
                msg.sender,
                block.timestamp,
                guessTypes[i] == 2, // higher (for backward compatibility)
                guessedSuits[i],
                newNumber,
                newSuit,
                isWin,
                isSuitWin,
                userStats.streak,
                superGemEarned + achievementBonus,
                userStats.totalPlays,
                userStats.totalWins,
                userStats.superGemPoints,
                userStats.bestStreak
            );

            // Emit Joker card event if Joker was drawn
            if (newNumber == 0) {
                emit JokerCardDrawn(
                    msg.sender,
                    block.timestamp,
                    isJokerWin ? Constants.JOKER_BONUS_MULTIPLIER : 0
                );
            }
        }

        userStats.currentNumber = currentNumber;
        userStats.currentSuit = currentSuit;

        // Consume credits: first use free daily guesses, then extra credits
        CardWarsMarketplace marketplaceContractBatch = CardWarsMarketplace(
            payable(address(marketplace))
        );

        for (uint256 i = 0; i < guessTypes.length; i++) {
            // Skip credit consumption for first guess if Burn It is used
            if (useBurnIt && i == 0) {
                continue; // First guess uses Burn It, no additional credit needed
            }

            // Use free daily guesses first
            if (dailyGuessCount[msg.sender] < Constants.DAILY_FREE_GUESSES) {
                dailyGuessCount[msg.sender]++;
            } else {
                // Use extra credits
                bool consumed = marketplaceContractBatch.consumeExtraCredits(
                    msg.sender,
                    1
                );
                if (!consumed) {
                    revert InsufficientCredits();
                }
            }
        }

        uint256 batchSize = guessTypes.length;
        if (totalGuesses > type(uint256).max - batchSize) {
            revert Overflow();
        }
        if (userGuessCount[msg.sender] > type(uint256).max - batchSize) {
            revert Overflow();
        }
        unchecked {
            totalGuesses += batchSize;
            userGuessCount[msg.sender] += batchSize;
        }
        ctx.completeEffects();

        ctx.requireInteractions();
        for (uint256 i = 0; i < guessTypes.length; i++) {
            boostContract.consumeBoost(msg.sender);
        }

        if (oldBestStreak < userStats.bestStreak) {
            emit BestStreakUpdated(
                msg.sender,
                block.timestamp,
                oldBestStreak,
                userStats.bestStreak
            );
        }

        uint256 winRate = userStats.totalPlays > 0
            ? (userStats.totalWins * 100) / userStats.totalPlays
            : 0;

        // Update weekly leaderboard for player (batch)
        if (totalSuperGems > 0) {
            _updateWeeklyPlayerLeaderboard(msg.sender, totalSuperGems);
        }

        emit BatchGuessResult(
            msg.sender,
            block.timestamp,
            guessTypes.length,
            totalWins,
            totalSuperGems,
            userStats.streak,
            userStats.totalPlays,
            userStats.totalWins,
            userStats.superGemPoints,
            userStats.bestStreak
        );

        emit StatsUpdated(
            msg.sender,
            block.timestamp,
            userStats.totalPlays,
            userStats.totalWins,
            userStats.superGemPoints,
            userStats.bestStreak,
            userStats.streak,
            winRate
        );

        _trackEvent(
            msg.sender,
            "BatchGuessResult",
            abi.encode(guessTypes.length, totalWins, totalSuperGems)
        );
    }

    function getUserStats(
        address user
    )
        external
        view
        override
        returns (
            uint256 currentNumber,
            uint8 currentSuit,
            uint256 streak,
            uint256 totalPlays,
            uint256 totalWins,
            uint256 superGemPoints,
            uint256 bestStreak
        )
    {
        HiLoStats memory userStats = stats[user];
        return (
            userStats.currentNumber,
            uint8(userStats.currentSuit),
            userStats.streak,
            userStats.totalPlays,
            userStats.totalWins,
            userStats.superGemPoints,
            userStats.bestStreak
        );
    }

    function getPlayerCount() external view returns (uint256) {
        return players.length;
    }

    function getPlayerAddress(uint256 index) external view returns (address) {
        if (index >= players.length) {
            revert InvalidAddress();
        }
        return players[index];
    }

    function getUserRank(
        address user,
        uint8 sortBy
    ) external view returns (uint256) {
        if (!isPlayer[user]) return 0;

        HiLoStats memory userStats = stats[user];
        uint256 userValue = 0;

        if (sortBy == 0) {
            userValue = userStats.totalWins;
        } else if (sortBy == 1) {
            userValue = userStats.bestStreak;
        } else if (sortBy == 2) {
            userValue = userStats.superGemPoints;
        }

        uint256 rank = 1;
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == user) continue;
            HiLoStats memory otherStats = stats[players[i]];

            uint256 otherValue = 0;
            if (sortBy == 0) {
                otherValue = otherStats.totalWins;
            } else if (sortBy == 1) {
                otherValue = otherStats.bestStreak;
            } else if (sortBy == 2) {
                otherValue = otherStats.superGemPoints;
            }

            if (otherValue > userValue) {
                rank++;
            }
        }

        return rank;
    }

    function getTopPlayers(
        uint256 limit,
        uint8 sortBy
    )
        external
        view
        returns (
            address[] memory addresses,
            uint256[] memory totalWins,
            uint256[] memory bestStreaks,
            uint256[] memory superGemPoints,
            uint256[] memory winRates
        )
    {
        if (limit == 0) {
            return (
                new address[](0),
                new uint256[](0),
                new uint256[](0),
                new uint256[](0),
                new uint256[](0)
            );
        }
        if (players.length == 0) {
            return (
                new address[](0),
                new uint256[](0),
                new uint256[](0),
                new uint256[](0),
                new uint256[](0)
            );
        }

        uint256 maxLimit = limit > 100 ? 100 : limit;
        uint256 count = players.length < maxLimit ? players.length : maxLimit;
        addresses = new address[](count);
        totalWins = new uint256[](count);
        bestStreaks = new uint256[](count);
        superGemPoints = new uint256[](count);
        winRates = new uint256[](count);

        address[] memory sortedPlayers = new address[](players.length);
        uint256[] memory values = new uint256[](players.length);

        for (uint256 i = 0; i < players.length; i++) {
            sortedPlayers[i] = players[i];
            HiLoStats memory playerStats = stats[players[i]];

            if (sortBy == 0) {
                values[i] = playerStats.totalWins;
            } else if (sortBy == 1) {
                values[i] = playerStats.bestStreak;
            } else if (sortBy == 2) {
                values[i] = playerStats.superGemPoints;
            }
        }

        for (uint256 i = 0; i < count; i++) {
            uint256 maxIndex = i;
            for (uint256 j = i + 1; j < players.length; j++) {
                if (values[j] > values[maxIndex]) {
                    maxIndex = j;
                }
            }
            if (maxIndex != i) {
                uint256 tempValue = values[i];
                address tempAddr = sortedPlayers[i];
                values[i] = values[maxIndex];
                sortedPlayers[i] = sortedPlayers[maxIndex];
                values[maxIndex] = tempValue;
                sortedPlayers[maxIndex] = tempAddr;
            }
        }

        for (uint256 i = 0; i < count; i++) {
            addresses[i] = sortedPlayers[i];
            HiLoStats memory playerStats = stats[sortedPlayers[i]];
            totalWins[i] = playerStats.totalWins;
            bestStreaks[i] = playerStats.bestStreak;
            superGemPoints[i] = playerStats.superGemPoints;
            winRates[i] = playerStats.totalPlays > 0
                ? (playerStats.totalWins * 100) / playerStats.totalPlays
                : 0;
        }
    }

    function resetGame() external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        HiLoStats storage userStats = stats[msg.sender];

        ctx.requireChecks();
        if (userStats.currentNumber == 0) {
            revert GameNotStarted();
        }

        // Check hourly reset limit (3 per hour)
        uint256 currentHour = block.timestamp / 1 hours;

        // Reset count if it's a new hour
        if (lastResetHour[msg.sender] != currentHour) {
            resetCountThisHour[msg.sender] = 0;
            lastResetHour[msg.sender] = currentHour;
        }

        // Check if user has exceeded hourly limit (max 3 resets per hour)
        // After 3 resets, count will be 3, so we check >= 3 before incrementing
        if (resetCountThisHour[msg.sender] >= 3) {
            revert ResetGameLimitExceeded();
        }

        ctx.completeChecks();

        ctx.requireEffects();
        uint256 previousNumber = userStats.currentNumber;
        Suit previousSuit = userStats.currentSuit;

        userStats.currentNumber = 0;
        userStats.currentSuit = Suit.Spades;
        userStats.streak = 0;
        consecutiveCorrectGuesses[msg.sender] = 0; // Reset consecutive guesses on game reset

        // Increment reset count for current hour
        resetCountThisHour[msg.sender]++;

        ctx.completeEffects();

        ctx.requireInteractions();
        emit GameReset(
            msg.sender,
            block.timestamp,
            previousNumber,
            previousSuit
        );
        _trackEvent(
            msg.sender,
            "GameReset",
            abi.encode(previousNumber, uint8(previousSuit))
        );
    }

    function _trackEvent(
        address user,
        string memory eventType,
        bytes memory data
    ) internal {
        bytes32 eventId = EventLib.generateEventId(
            address(this),
            eventType,
            user,
            block.timestamp
        );

        ITrackable.TrackedEvent memory trackedEvent = ITrackable.TrackedEvent({
            eventId: eventId,
            user: user,
            eventType: eventType,
            timestamp: block.timestamp,
            data: data
        });

        trackedEvents[eventId] = trackedEvent;
        userEventIds[user].push(eventId);

        unchecked {
            userEventCounts[user]++;
        }
    }

    function getEventHistory(
        address user,
        uint256 from,
        uint256 to
    ) external view override returns (ITrackable.TrackedEvent[] memory) {
        uint256 count = userEventCounts[user];
        if (count == 0) {
            return new ITrackable.TrackedEvent[](0);
        }

        if (to > count) {
            to = count;
        }
        if (from >= to) {
            return new ITrackable.TrackedEvent[](0);
        }

        uint256 length = to - from;
        ITrackable.TrackedEvent[] memory events = new ITrackable.TrackedEvent[](
            length
        );
        bytes32[] memory eventIds = userEventIds[user];

        for (uint256 i = 0; i < length; i++) {
            events[i] = trackedEvents[eventIds[from + i]];
        }

        return events;
    }

    function getEventCount(
        address user
    ) external view override returns (uint256) {
        return userEventCounts[user];
    }

    function getEventById(
        bytes32 eventId
    ) external view override returns (ITrackable.TrackedEvent memory) {
        return trackedEvents[eventId];
    }

    // Removed redundant view functions - use public mappings directly

    function getUserAchievements(
        address user
    )
        external
        view
        returns (uint256 consecutiveCorrect, uint256 lastMilestone)
    {
        return (
            consecutiveCorrectGuesses[user],
            lastAchievementMilestone[user]
        );
    }

    function getCurrentWeeklyLeaderboard()
        external
        view
        returns (
            address topPlayer,
            uint256 topPlayerScore,
            uint256 topClanId,
            uint256 topClanScore,
            uint256 weekNumber,
            uint256 weekStartTime,
            uint256 weekEndTime
        )
    {
        WeeklyLeaderboard memory leaderboard = weeklyLeaderboards[
            currentWeekNumber
        ];
        return (
            leaderboard.topPlayer,
            leaderboard.topPlayerScore,
            leaderboard.topClanId,
            leaderboard.topClanScore,
            currentWeekNumber,
            leaderboard.weekStartTime,
            leaderboard.weekEndTime
        );
    }

    function getWeeklyLeaderboard(
        uint256 weekNumber
    )
        external
        view
        returns (
            address topPlayer,
            uint256 topPlayerScore,
            uint256 topClanId,
            uint256 topClanScore,
            uint256 weekStartTime,
            uint256 weekEndTime
        )
    {
        WeeklyLeaderboard memory leaderboard = weeklyLeaderboards[weekNumber];
        return (
            leaderboard.topPlayer,
            leaderboard.topPlayerScore,
            leaderboard.topClanId,
            leaderboard.topClanScore,
            leaderboard.weekStartTime,
            leaderboard.weekEndTime
        );
    }

    function getWeeklyPlayerScore(
        address player
    ) external view returns (uint256) {
        return weeklyPlayerScores[player];
    }

    function updateWeeklyClanLeaderboard() external {
        _updateWeeklyClanLeaderboard();
    }

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
        )
    {
        uint256 maxIterations = players.length > 1000 ? 1000 : players.length;
        address[] memory filteredPlayers = new address[](maxIterations);
        uint256 count = 0;

        for (uint256 i = 0; i < maxIterations; i++) {
            HiLoStats memory playerStats = stats[players[i]];
            if (playerStats.totalPlays > 0) {
                uint256 winRate = (playerStats.totalWins * 10000) /
                    playerStats.totalPlays;
                if (winRate >= minWinRate) {
                    filteredPlayers[count] = players[i];
                    count++;
                }
            }
        }

        uint256 resultCount = count < limit ? count : limit;
        addresses = new address[](resultCount);
        totalWins = new uint256[](resultCount);
        totalPlays = new uint256[](resultCount);
        winRates = new uint256[](resultCount);

        for (uint256 i = 0; i < resultCount; i++) {
            addresses[i] = filteredPlayers[i];
            HiLoStats memory playerStats = stats[filteredPlayers[i]];
            totalWins[i] = playerStats.totalWins;
            totalPlays[i] = playerStats.totalPlays;
            winRates[i] = playerStats.totalPlays > 0
                ? (playerStats.totalWins * 10000) / playerStats.totalPlays
                : 0;
        }
    }

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
        )
    {
        uint256 maxIterations = players.length > 1000 ? 1000 : players.length;
        address[] memory filteredPlayers = new address[](maxIterations);
        uint256 count = 0;

        for (uint256 i = 0; i < maxIterations; i++) {
            HiLoStats memory playerStats = stats[players[i]];
            if (playerStats.bestStreak >= minStreak) {
                filteredPlayers[count] = players[i];
                count++;
            }
        }

        uint256 resultCount = count < limit ? count : limit;
        addresses = new address[](resultCount);
        bestStreaks = new uint256[](resultCount);
        currentStreaks = new uint256[](resultCount);

        for (uint256 i = 0; i < resultCount; i++) {
            addresses[i] = filteredPlayers[i];
            HiLoStats memory playerStats = stats[filteredPlayers[i]];
            bestStreaks[i] = playerStats.bestStreak;
            currentStreaks[i] = playerStats.streak;
        }
    }

    function getPlayersBySuperGems(
        uint256 minSuperGems,
        uint256 limit
    )
        external
        view
        returns (address[] memory addresses, uint256[] memory superGemPoints)
    {
        uint256 maxIterations = players.length > 1000 ? 1000 : players.length;
        address[] memory filteredPlayers = new address[](maxIterations);
        uint256 count = 0;

        for (uint256 i = 0; i < maxIterations; i++) {
            HiLoStats memory playerStats = stats[players[i]];
            if (playerStats.superGemPoints >= minSuperGems) {
                filteredPlayers[count] = players[i];
                count++;
            }
        }

        uint256 resultCount = count < limit ? count : limit;
        addresses = new address[](resultCount);
        superGemPoints = new uint256[](resultCount);

        for (uint256 i = 0; i < resultCount; i++) {
            addresses[i] = filteredPlayers[i];
            superGemPoints[i] = stats[filteredPlayers[i]].superGemPoints;
        }
    }

    function getActivePlayers(
        uint256 hoursParam
    ) external view returns (address[] memory) {
        uint256 timeThreshold = block.timestamp - (hoursParam * 3600);
        uint256 maxIterations = players.length > 1000 ? 1000 : players.length;
        address[] memory activePlayers = new address[](maxIterations);
        uint256 count = 0;

        for (uint256 i = 0; i < maxIterations; i++) {
            if (userGameStartCount[players[i]] > 0) {
                uint256 lastGuessDayTimestamp = lastGuessDay[players[i]] *
                    1 days;
                if (lastGuessDayTimestamp >= timeThreshold) {
                    activePlayers[count] = players[i];
                    count++;
                }
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = activePlayers[i];
        }
        return result;
    }

    function getPlayersWithMembership(
        uint8 tier
    ) external view returns (address[] memory) {
        if (address(marketplace) == address(0)) {
            return new address[](0);
        }

        uint256 maxIterations = players.length > 500 ? 500 : players.length;
        address[] memory playersWithMembership = new address[](maxIterations);
        uint256 count = 0;

        for (uint256 i = 0; i < maxIterations; i++) {
            (
                IMarketplace.MembershipTier membershipTier,
                ,
                uint256 expiresAt
            ) = marketplace.getUserMembership(players[i]);
            if (uint8(membershipTier) == tier && expiresAt > block.timestamp) {
                playersWithMembership[count] = players[i];
                count++;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = playersWithMembership[i];
        }
        return result;
    }

    // Farcaster/Profile functions moved to CardWarsProfile contract

    function getAllPlayers() external view returns (address[] memory) {
        return players;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
