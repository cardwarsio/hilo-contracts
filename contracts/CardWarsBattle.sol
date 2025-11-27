// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IBattle.sol";
import "./interfaces/IHiLo.sol";
import "./interfaces/IClan.sol";
import "./CardWarsHiLo.sol";
import "./CardWarsMarketplace.sol";
import "./utils/Errors.sol";
import "./libraries/CEILib.sol";

contract CardWarsBattle is IBattle, ReentrancyGuard, Pausable, Ownable, AccessControl {
    using CEILib for CEILib.CEIContext;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    CardWarsHiLo public hiloContract;
    IClan public clanContract;
    CardWarsMarketplace public marketplaceContract;

    uint256 public battleCounter;
    mapping(uint256 => Battle) public battles;
    mapping(address => uint256[]) public userBattles;
    mapping(address => uint256) public battleWins;
    mapping(address => uint256) public battleLosses;

    uint256 public constant BATTLE_ROUNDS = 10; // 10 rounds per battle
    uint256 public constant BATTLE_TIMEOUT = 48 hours; // Battle must complete in 48 hours
    uint256 public constant TURN_TIMEOUT = 48 hours; // Player must play within 48 hours

    address[] public battleQueue; // Queue for random matchmaking
    mapping(address => bool) public inQueue; // Is user in queue
    mapping(address => uint256[]) public pendingInvitations; // User => battleIds where they are invited
    mapping(address => uint256[]) public sentInvitations; // User => battleIds they sent

    constructor(address payable _hiloContract) Ownable(msg.sender) {
        if (_hiloContract == address(0)) {
            revert InvalidAddress();
        }
        hiloContract = CardWarsHiLo(_hiloContract);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    function createBattle(
        address opponent
    ) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (opponent == address(0) || opponent == msg.sender) {
            revert InvalidAddress();
        }

        ctx.completeChecks();

        ctx.requireEffects();
        battleCounter++;
        uint256 battleId = battleCounter;

        battles[battleId] = Battle({
            challenger: msg.sender,
            opponent: opponent,
            status: BattleStatus.Pending,
            betAmount: 0,
            startedAt: 0,
            completedAt: 0,
            lastMoveAt: 0,
            currentPlayer: address(0),
            winner: address(0),
            challengerScore: 0,
            opponentScore: 0,
            rounds: 0,
            currentCardNumber: 0,
            currentCardSuit: 0,
            previousCardNumber: 0,
            previousCardSuit: 0,
            challengerPlayed: false,
            opponentPlayed: false
        });

        userBattles[msg.sender].push(battleId);
        userBattles[opponent].push(battleId);
        pendingInvitations[opponent].push(battleId);
        sentInvitations[msg.sender].push(battleId);

        ctx.completeEffects();

        ctx.requireInteractions();
        emit BattleCreated(battleId, msg.sender, opponent, 0, block.timestamp);
        emit BattleInvitationSent(
            battleId,
            msg.sender,
            opponent,
            block.timestamp
        );
    }

    function acceptBattle(
        uint256 battleId
    ) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        Battle storage battle = battles[battleId];

        ctx.requireChecks();
        if (battle.status != BattleStatus.Pending) {
            revert();
        }
        if (battle.opponent != msg.sender) {
            revert Unauthorized();
        }

        ctx.completeChecks();

        ctx.requireEffects();
        battle.status = BattleStatus.Active;
        battle.startedAt = block.timestamp;
        battle.lastMoveAt = block.timestamp;
        battle.currentPlayer = battle.challenger; // Challenger plays first

        // Generate first card for battle (shared between both players)
        (uint256 firstCard, uint8 firstSuit) = _generateBattleCard(battleId, 0);
        battle.currentCardNumber = firstCard;
        battle.currentCardSuit = firstSuit;
        battle.previousCardNumber = firstCard; // First card is both current and previous
        battle.previousCardSuit = firstSuit;

        _removeInvitation(battleId, msg.sender);

        ctx.completeEffects();

        ctx.requireInteractions();
        emit BattleStarted(
            battleId,
            battle.challenger,
            battle.opponent,
            block.timestamp
        );
        emit BattleInvitationAccepted(battleId, msg.sender, block.timestamp);
    }

    function playBattleRound(
        uint256 battleId,
        uint8 guessType,
        IHiLo.Suit guessedSuit
    ) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        Battle storage battle = battles[battleId];

        ctx.requireChecks();
        if (battle.status != BattleStatus.Active) {
            revert BattleNotActive();
        }
        if (msg.sender != battle.challenger && msg.sender != battle.opponent) {
            revert Unauthorized();
        }
        if (battle.currentPlayer != msg.sender) {
            revert Unauthorized();
        }
        if (battle.rounds >= BATTLE_ROUNDS) {
            revert BattleAlreadyCompleted();
        }
        if (block.timestamp > battle.lastMoveAt + TURN_TIMEOUT) {
            _handleTimeout(battleId);
            revert BattleNotActive();
        }
        if (block.timestamp > battle.startedAt + BATTLE_TIMEOUT) {
            _handleBattleTimeout(battleId);
            revert BattleNotActive();
        }

        ctx.completeChecks();

        ctx.requireEffects();
        bool isChallenger = (msg.sender == battle.challenger);

        // Both players use the same card for this round
        uint256 currentCard = battle.currentCardNumber;
        uint8 currentSuit = battle.currentCardSuit;
        uint256 previousCard = battle.previousCardNumber;

        // Mark player as played this round
        if (isChallenger) {
            if (battle.challengerPlayed) {
                revert AlreadyPlayed(); // Already played this round
            }
            battle.challengerPlayed = true;
        } else {
            if (battle.opponentPlayed) {
                revert AlreadyPlayed(); // Already played this round
            }
            battle.opponentPlayed = true;
        }

        // Calculate score based on battle card (not individual HiLo game)
        bool isWin = false;
        bool isSuitWin = false;

        if (guessType == 0) {
            // Lower guess
            isWin = (currentCard != 0) && (currentCard < previousCard);
        } else if (guessType == 1) {
            // Joker guess
            isWin = (currentCard == 0);
        } else if (guessType == 2) {
            // Higher guess
            isWin = (currentCard != 0) && (currentCard > previousCard);
        }

        // Check suit prediction
        if (guessedSuit != IHiLo.Suit.None && currentCard != 0) {
            isSuitWin = (uint8(guessedSuit) == currentSuit);
        }

        // Calculate round score (same formula as HiLo but for battle)
        uint256 roundScore = 0;
        if (isWin) {
            if (isSuitWin) {
                roundScore = 4; // 2x base for suit win
            } else {
                roundScore = 2; // Base score
            }
            if (currentCard == 0) {
                roundScore = 200; // Joker card bonus (100x)
            }
        }

        if (isChallenger) {
            battle.challengerScore += roundScore;
        } else {
            battle.opponentScore += roundScore;
        }

        battle.lastMoveAt = block.timestamp;

        // Check if both players played this round
        bool bothPlayed = battle.challengerPlayed && battle.opponentPlayed;

        if (bothPlayed) {
            // Both players played, move to next round
            battle.rounds++;

            // Update previous card for next round
            battle.previousCardNumber = currentCard;
            battle.previousCardSuit = currentSuit;

            // Reset play flags
            battle.challengerPlayed = false;
            battle.opponentPlayed = false;

            // Generate new card for next round
            if (battle.rounds < BATTLE_ROUNDS) {
                (uint256 newCard, uint8 newSuit) = _generateBattleCard(
                    battleId,
                    battle.rounds
                );
                battle.currentCardNumber = newCard;
                battle.currentCardSuit = newSuit;
                battle.currentPlayer = battle.challenger; // Challenger starts next round
            } else {
                battle.currentPlayer = address(0);
            }
        } else {
            // Other player still needs to play
            battle.currentPlayer = isChallenger
                ? battle.opponent
                : battle.challenger;
        }

        ctx.completeEffects();

        ctx.requireInteractions();
        emit BattleRoundCompleted(
            battleId,
            msg.sender,
            roundScore > 0,
            roundScore,
            block.timestamp
        );

        if (battle.rounds >= BATTLE_ROUNDS) {
            _completeBattle(battleId);
        }
    }

    function _generateBattleCard(
        uint256 battleId,
        uint256 roundNumber
    ) internal view returns (uint256 cardValue, uint8 suitValue) {
        // Use battle ID + round number as seed for consistent card generation
        // Both players will see the same card for the same round
        uint256 seed = uint256(
            keccak256(abi.encodePacked(battleId, roundNumber, block.prevrandao))
        );

        // Generate card using battle-specific seed
        uint256 cardIndex = seed % 53; // 0-52 (0 = Joker, 1-52 = normal cards)

        if (cardIndex == 0) {
            return (0, 5); // Joker card
        } else {
            uint256 idx = cardIndex - 1; // 0-51
            cardValue = (idx % 13) + 1; // 1-13 (A=1, 2-10, J=11, Q=12, K=13)
            suitValue = uint8(idx / 13); // 0-3 (Spades, Hearts, Diamonds, Clubs)
            return (cardValue, suitValue);
        }
    }

    function cancelBattle(uint256 battleId) external nonReentrant {
        Battle storage battle = battles[battleId];

        if (battle.status != BattleStatus.Pending) {
            revert BattleNotActive();
        }
        if (battle.challenger != msg.sender) {
            revert Unauthorized();
        }

        battle.status = BattleStatus.Cancelled;

        emit BattleCancelled(battleId, msg.sender, block.timestamp);
    }

    function _completeBattle(uint256 battleId) internal {
        Battle storage battle = battles[battleId];

        battle.status = BattleStatus.Completed;
        battle.completedAt = block.timestamp;

        address winner;
        uint256 winnerScore = 0;

        if (battle.challengerScore > battle.opponentScore) {
            winner = battle.challenger;
            battle.winner = battle.challenger;
            winnerScore = battle.challengerScore;
            battleWins[battle.challenger]++;
            battleLosses[battle.opponent]++;
        } else if (battle.opponentScore > battle.challengerScore) {
            winner = battle.opponent;
            battle.winner = battle.opponent;
            winnerScore = battle.opponentScore;
            battleWins[battle.opponent]++;
            battleLosses[battle.challenger]++;
        } else {
            winner = address(0);
        }

        if (winner != address(0) && address(clanContract) != address(0)) {
            uint256 winnerClanId = clanContract.userClan(winner);
            if (winnerClanId > 0) {
                clanContract.addBattleScore(winnerClanId, winnerScore);
            }
        }

        emit BattleCompleted(
            battleId,
            winner,
            winner == battle.challenger ? battle.opponent : battle.challenger,
            0,
            block.timestamp
        );
    }

    function getUserBattleStats(
        address user
    )
        external
        view
        returns (uint256 wins, uint256 losses, uint256 totalBattles)
    {
        wins = battleWins[user];
        losses = battleLosses[user];
        totalBattles = userBattles[user].length;
    }

    function getBattle(uint256 battleId) external view returns (Battle memory) {
        Battle memory battle = battles[battleId];
        if (battle.challenger == address(0) && battle.opponent == address(0)) {
            revert BattleNotFound();
        }
        return battle;
    }

    function getUserBattles(
        address user
    ) external view returns (uint256[] memory) {
        return userBattles[user];
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setHiloContract(address payable _hiloContract) external onlyOwner {
        if (_hiloContract == address(0)) {
            revert InvalidAddress();
        }
        hiloContract = CardWarsHiLo(_hiloContract);
    }

    function setClanContract(address _clanContract) external onlyOwner {
        if (_clanContract == address(0)) {
            revert InvalidAddress();
        }
        clanContract = IClan(_clanContract);
    }

    function setMarketplaceContract(
        address _marketplaceContract
    ) external onlyOwner {
        if (_marketplaceContract == address(0)) {
            revert InvalidAddress();
        }
        marketplaceContract = CardWarsMarketplace(_marketplaceContract);
    }

    function sendBattleEmoji(
        uint256 battleId,
        uint256 emojiItemId
    ) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        Battle storage battle = battles[battleId];

        ctx.requireChecks();
        if (battle.status != BattleStatus.Completed) {
            revert BattleNotCompleted(); // Battle must be completed
        }
        if (msg.sender != battle.challenger && msg.sender != battle.opponent) {
            revert Unauthorized();
        }
        if (address(marketplaceContract) == address(0)) {
            revert InvalidAddress();
        }
        // Check if user has the emoji
        if (!marketplaceContract.hasBattleEmoji(msg.sender, emojiItemId)) {
            revert EmojiNotOwned(); // User doesn't have this emoji
        }
        ctx.completeChecks();

        ctx.requireEffects();
        // Consume the emoji
        bool consumed = marketplaceContract.consumeBattleEmoji(
            msg.sender,
            emojiItemId
        );
        if (!consumed) {
            revert EmojiConsumeFailed(); // Failed to consume emoji
        }
        ctx.completeEffects();

        ctx.requireInteractions();
        address recipient = msg.sender == battle.challenger
            ? battle.opponent
            : battle.challenger;
        emit BattleEmojiSent(
            battleId,
            msg.sender,
            recipient,
            emojiItemId,
            block.timestamp
        );
    }

    function joinQueue() external nonReentrant whenNotPaused {
        if (inQueue[msg.sender]) {
            revert AlreadyInQueue();
        }
        battleQueue.push(msg.sender);
        inQueue[msg.sender] = true;
        emit PlayerJoinedQueue(msg.sender, block.timestamp);
    }

    function leaveQueue() external nonReentrant {
        if (!inQueue[msg.sender]) {
            revert NotInQueue();
        }
        _removeFromQueue(msg.sender);
        emit PlayerLeftQueue(msg.sender, block.timestamp);
    }

    function findRandomOpponent() external nonReentrant whenNotPaused {
        if (!inQueue[msg.sender]) {
            revert NotInQueue();
        }
        if (battleQueue.length < 2) {
            revert QueueEmpty();
        }

        uint256 randomIndex = uint256(
            keccak256(
                abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)
            )
        ) % battleQueue.length;

        address opponent = battleQueue[randomIndex];
        if (opponent == msg.sender) {
            if (battleQueue.length > 1) {
                opponent = battleQueue[(randomIndex + 1) % battleQueue.length];
            } else {
                revert QueueEmpty();
            }
        }

        _removeFromQueue(msg.sender);
        _removeFromQueue(opponent);

        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (opponent == address(0) || opponent == msg.sender) {
            revert InvalidAddress();
        }

        ctx.completeChecks();

        ctx.requireEffects();
        battleCounter++;
        uint256 battleId = battleCounter;

        battles[battleId] = Battle({
            challenger: msg.sender,
            opponent: opponent,
            status: BattleStatus.Pending,
            betAmount: 0,
            startedAt: 0,
            completedAt: 0,
            lastMoveAt: 0,
            currentPlayer: address(0),
            winner: address(0),
            challengerScore: 0,
            opponentScore: 0,
            rounds: 0,
            currentCardNumber: 0,
            currentCardSuit: 0,
            previousCardNumber: 0,
            previousCardSuit: 0,
            challengerPlayed: false,
            opponentPlayed: false
        });

        userBattles[msg.sender].push(battleId);
        userBattles[opponent].push(battleId);
        pendingInvitations[opponent].push(battleId);
        sentInvitations[msg.sender].push(battleId);

        ctx.completeEffects();

        ctx.requireInteractions();
        emit BattleCreated(battleId, msg.sender, opponent, 0, block.timestamp);
        emit BattleInvitationSent(
            battleId,
            msg.sender,
            opponent,
            block.timestamp
        );
    }

    function rejectBattleInvitation(uint256 battleId) external nonReentrant {
        Battle storage battle = battles[battleId];
        if (battle.status != BattleStatus.Pending) {
            revert BattleNotActive();
        }
        if (battle.opponent != msg.sender) {
            revert Unauthorized();
        }

        battle.status = BattleStatus.Cancelled;
        _removeInvitation(battleId, msg.sender);

        emit BattleInvitationRejected(battleId, msg.sender, block.timestamp);
        emit BattleCancelled(battleId, msg.sender, block.timestamp);
    }

    function _removeFromQueue(address player) internal {
        if (!inQueue[player]) {
            return;
        }
        for (uint256 i = 0; i < battleQueue.length; i++) {
            if (battleQueue[i] == player) {
                battleQueue[i] = battleQueue[battleQueue.length - 1];
                battleQueue.pop();
                inQueue[player] = false;
                break;
            }
        }
    }

    function _removeInvitation(uint256 battleId, address user) internal {
        uint256[] storage pending = pendingInvitations[user];
        for (uint256 i = 0; i < pending.length; i++) {
            if (pending[i] == battleId) {
                pending[i] = pending[pending.length - 1];
                pending.pop();
                break;
            }
        }
    }

    function _handleTimeout(uint256 battleId) internal {
        Battle storage battle = battles[battleId];
        address loser = battle.currentPlayer;
        address winner = loser == battle.challenger
            ? battle.opponent
            : battle.challenger;

        battle.status = BattleStatus.Completed;
        battle.completedAt = block.timestamp;
        battle.winner = winner;
        battleWins[winner]++;
        battleLosses[loser]++;

        if (address(clanContract) != address(0)) {
            uint256 winnerClanId = clanContract.userClan(winner);
            if (winnerClanId > 0) {
                clanContract.addBattleScore(
                    winnerClanId,
                    battle.challengerScore > battle.opponentScore
                        ? battle.challengerScore
                        : battle.opponentScore
                );
            }
        }

        emit BattleExpired(battleId, winner, loser, block.timestamp);
        emit BattleCompleted(battleId, winner, loser, 0, block.timestamp);
    }

    function _handleBattleTimeout(uint256 battleId) internal {
        Battle storage battle = battles[battleId];
        address winner = battle.challengerScore > battle.opponentScore
            ? battle.challenger
            : battle.opponent;
        address loser = winner == battle.challenger
            ? battle.opponent
            : battle.challenger;

        if (battle.challengerScore == battle.opponentScore) {
            winner = address(0);
        }

        battle.status = BattleStatus.Expired;
        battle.completedAt = block.timestamp;
        if (winner != address(0)) {
            battle.winner = winner;
            battleWins[winner]++;
            battleLosses[loser]++;

            if (address(clanContract) != address(0)) {
                uint256 winnerClanId = clanContract.userClan(winner);
                if (winnerClanId > 0) {
                    clanContract.addBattleScore(
                        winnerClanId,
                        battle.challengerScore > battle.opponentScore
                            ? battle.challengerScore
                            : battle.opponentScore
                    );
                }
            }
        }

        emit BattleExpired(battleId, winner, loser, block.timestamp);
        emit BattleCompleted(battleId, winner, loser, 0, block.timestamp);
    }

    function getBattleQueue() external view returns (address[] memory) {
        return battleQueue;
    }

    function getPendingInvitations(
        address user
    ) external view returns (uint256[] memory) {
        return pendingInvitations[user];
    }

    function getSentInvitations(
        address user
    ) external view returns (uint256[] memory) {
        return sentInvitations[user];
    }

    function _containsAddress(
        address[] memory arr,
        address addr,
        uint256 length
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < length; i++) {
            if (arr[i] == addr) {
                return true;
            }
        }
        return false;
    }

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

        uint256 maxLimit = limit > 100 ? 100 : limit;
        uint256 maxBattles = battleCounter > 500 ? 500 : battleCounter;
        address[] memory allPlayers = new address[](battleQueue.length + maxBattles * 2);
        uint256 playerCount = 0;

        uint256 queueLength = battleQueue.length > 100 ? 100 : battleQueue.length;
        for (uint256 i = 0; i < queueLength; i++) {
            if (!_containsAddress(allPlayers, battleQueue[i], playerCount)) {
                allPlayers[playerCount] = battleQueue[i];
                playerCount++;
            }
        }

        for (uint256 i = 1; i <= maxBattles; i++) {
            Battle memory battle = battles[i];
            if (battle.challenger != address(0)) {
                if (!_containsAddress(allPlayers, battle.challenger, playerCount)) {
                    allPlayers[playerCount] = battle.challenger;
                    playerCount++;
                }
                if (battle.opponent != address(0) && !_containsAddress(allPlayers, battle.opponent, playerCount)) {
                    allPlayers[playerCount] = battle.opponent;
                    playerCount++;
                }
            }
        }

        if (playerCount == 0) {
            return (
                new address[](0),
                new uint256[](0),
                new uint256[](0),
                new uint256[](0),
                new uint256[](0)
            );
        }

        address[] memory sortedPlayers = new address[](playerCount);
        uint256[] memory values = new uint256[](playerCount);

        for (uint256 i = 0; i < playerCount; i++) {
            sortedPlayers[i] = allPlayers[i];
            uint256 playerWins = battleWins[allPlayers[i]];
            uint256 playerLosses = battleLosses[allPlayers[i]];
            uint256 playerTotalBattles = userBattles[allPlayers[i]].length;

            if (sortBy == 0) {
                values[i] = playerWins;
            } else if (sortBy == 1) {
                values[i] = playerTotalBattles > 0
                    ? (playerWins * 10000) / playerTotalBattles
                    : 0;
            } else if (sortBy == 2) {
                values[i] = playerTotalBattles;
            } else {
                values[i] = playerLosses;
            }
        }

        uint256 count = playerCount < maxLimit ? playerCount : maxLimit;

        for (uint256 i = 0; i < count; i++) {
            uint256 maxIndex = i;
            for (uint256 j = i + 1; j < playerCount; j++) {
                if (values[j] > values[maxIndex]) {
                    maxIndex = j;
                }
            }
            if (maxIndex != i) {
                address tempAddr = sortedPlayers[i];
                uint256 tempVal = values[i];
                sortedPlayers[i] = sortedPlayers[maxIndex];
                values[i] = values[maxIndex];
                sortedPlayers[maxIndex] = tempAddr;
                values[maxIndex] = tempVal;
            }
        }

        addresses = new address[](count);
        wins = new uint256[](count);
        losses = new uint256[](count);
        winRates = new uint256[](count);
        totalBattles = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            addresses[i] = sortedPlayers[i];
            wins[i] = battleWins[sortedPlayers[i]];
            losses[i] = battleLosses[sortedPlayers[i]];
            totalBattles[i] = userBattles[sortedPlayers[i]].length;
            winRates[i] = totalBattles[i] > 0
                ? (wins[i] * 10000) / totalBattles[i]
                : 0;
        }
    }

    function getActiveBattlePlayers()
        external
        view
        returns (address[] memory)
    {
        address[] memory activePlayers = new address[](battleCounter * 2);
        uint256 count = 0;

        for (uint256 i = 1; i <= battleCounter; i++) {
            Battle memory battle = battles[i];
            if (battle.status == BattleStatus.Active) {
                if (battle.challenger != address(0) && !_containsAddress(activePlayers, battle.challenger, count)) {
                    activePlayers[count] = battle.challenger;
                    count++;
                }
                if (battle.opponent != address(0) && !_containsAddress(activePlayers, battle.opponent, count)) {
                    activePlayers[count] = battle.opponent;
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

    function getPlayersInQueueWithStats()
        external
        view
        returns (
            address[] memory addresses,
            uint256[] memory wins,
            uint256[] memory losses,
            uint256[] memory winRates,
            uint256[] memory totalBattles
        )
    {
        uint256 queueLength = battleQueue.length;
        addresses = new address[](queueLength);
        wins = new uint256[](queueLength);
        losses = new uint256[](queueLength);
        winRates = new uint256[](queueLength);
        totalBattles = new uint256[](queueLength);

        for (uint256 i = 0; i < queueLength; i++) {
            addresses[i] = battleQueue[i];
            wins[i] = battleWins[battleQueue[i]];
            losses[i] = battleLosses[battleQueue[i]];
            totalBattles[i] = userBattles[battleQueue[i]].length;
            winRates[i] = totalBattles[i] > 0
                ? (wins[i] * 10000) / totalBattles[i]
                : 0;
        }
    }

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
        )
    {
        address[] memory allPlayers = new address[](battleCounter * 2);
        uint256 playerCount = 0;

        for (uint256 i = 1; i <= battleCounter; i++) {
            Battle memory battle = battles[i];
            if (battle.challenger != address(0) && !_containsAddress(allPlayers, battle.challenger, playerCount)) {
                uint256 totalBattles = userBattles[battle.challenger].length;
                if (totalBattles > 0) {
                    uint256 winRate = (battleWins[battle.challenger] * 10000) /
                        totalBattles;
                    if (winRate >= minWinRate) {
                        allPlayers[playerCount] = battle.challenger;
                        playerCount++;
                    }
                }
            }
            if (
                battle.opponent != address(0) && !_containsAddress(allPlayers, battle.opponent, playerCount)
            ) {
                uint256 totalBattles = userBattles[battle.opponent].length;
                if (totalBattles > 0) {
                    uint256 winRate = (battleWins[battle.opponent] * 10000) /
                        totalBattles;
                    if (winRate >= minWinRate) {
                        allPlayers[playerCount] = battle.opponent;
                        playerCount++;
                    }
                }
            }
        }

        uint256 count = playerCount < limit ? playerCount : limit;
        addresses = new address[](count);
        wins = new uint256[](count);
        losses = new uint256[](count);
        winRates = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            addresses[i] = allPlayers[i];
            wins[i] = battleWins[allPlayers[i]];
            losses[i] = battleLosses[allPlayers[i]];
            uint256 totalBattles = userBattles[allPlayers[i]].length;
            winRates[i] = totalBattles > 0
                ? (wins[i] * 10000) / totalBattles
                : 0;
        }
    }

    function getRecentBattlePlayers(
        uint256 hoursParam,
        uint256 limit
    ) external view returns (address[] memory) {
        uint256 timeThreshold = block.timestamp - (hoursParam * 3600);
        address[] memory recentPlayers = new address[](battleCounter * 2);
        uint256 count = 0;

        for (uint256 i = 1; i <= battleCounter; i++) {
            Battle memory battle = battles[i];
            if (battle.startedAt >= timeThreshold || battle.completedAt >= timeThreshold) {
                if (battle.challenger != address(0) && !_containsAddress(recentPlayers, battle.challenger, count)) {
                    recentPlayers[count] = battle.challenger;
                    count++;
                }
                if (battle.opponent != address(0) && !_containsAddress(recentPlayers, battle.opponent, count)) {
                    recentPlayers[count] = battle.opponent;
                    count++;
                }
            }
        }

        uint256 resultCount = count < limit ? count : limit;
        address[] memory result = new address[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            result[i] = recentPlayers[i];
        }
        return result;
    }
}
