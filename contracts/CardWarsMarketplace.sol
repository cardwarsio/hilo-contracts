// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IHiLo.sol";
import "./interfaces/IMarketplace.sol";
import "./interfaces/IBoost.sol";
import "./interfaces/ITrackable.sol";
import "./libraries/CEILib.sol";
import "./libraries/EventLib.sol";
import "./utils/Errors.sol";
import "./utils/Constants.sol";

contract CardWarsMarketplace is
    IMarketplace,
    IBoost,
    ITrackable,
    Ownable,
    AccessControl,
    ReentrancyGuard,
    Pausable
{
    using CEILib for CEILib.CEIContext;
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    enum ItemType {
        Membership,
        Boost,
        ExtraCredits,
        StreakProtection, // Prevents streak from breaking on next loss
        MultiplierBoost, // Temporary multiplier boost (e.g., 2x for 1 hour)
        ClanCosmetic, // Cosmetic items for clans (flags, banners, etc.)
        BurnIt, // Skip card, auto correct guess (1 item = 1 guess)
        BattleEmoji // Animated emojis to send to opponent after battle (e.g., hammer, tissue, etc.)
    }

    enum PaymentToken {
        ETH,
        ERC20
    }

    struct PaymentTokenInfo {
        address tokenAddress;
        bool allowed;
        string symbol;
        uint8 decimals;
    }

    struct MarketplaceItem {
        uint256 id;
        string name;
        string description;
        uint256 price;
        address paymentToken;
        PaymentToken paymentTokenType;
        ItemType itemType;
        MembershipTier membershipTier;
        BoostType boostType;
        uint256 boostDuration;
        string metadataURI;
        bool active;
        uint256 supply;
        uint256 sold;
    }

    struct UserMembership {
        MembershipTier tier;
        uint64 purchasedAt;
        uint64 expiresAt;
    }

    struct UserBoost {
        BoostType boostType;
        uint64 activatedAt;
        uint64 expiresAt;
        uint256 remainingUses;
    }

    IHiLo public hiLoContract;
    uint256 public itemCounter;
    string public baseURI;
    address public battleContract;

    mapping(uint256 => MarketplaceItem) public items;
    mapping(address => UserMembership) public memberships;
    mapping(address => UserBoost) public boosts;
    mapping(address => uint256) public extraCredits;
    mapping(address => uint256) public burnItCredits; // Burn It credits (skip card, auto correct)
    mapping(address => bool) public streakProtection; // Streak protection active
    mapping(address => mapping(uint256 => uint256)) public userBattleEmojis; // user => emojiItemId => quantity (consumable)

    function consumeStreakProtection(address user) external {
        require(
            msg.sender == address(hiLoContract),
            "Only HiLo contract can consume"
        );
        streakProtection[user] = false;
    }
    mapping(address => uint256) public multiplierBoost; // Temporary multiplier (0 = no boost)
    mapping(address => uint256) public multiplierBoostExpires; // When multiplier boost expires

    address[] public allUsers;
    mapping(address => bool) public isUser;
    mapping(address => uint256) public userIndex;

    address[] public allowedPaymentTokens;
    mapping(address => PaymentTokenInfo) public paymentTokens;
    mapping(address => bool) public isPaymentToken;

    mapping(address => bytes32[]) public userEventIds;
    mapping(bytes32 => ITrackable.TrackedEvent) public trackedEvents;
    mapping(address => uint256) public userEventCounts;

    uint256 public totalItemsAdded;
    uint256 public totalPurchases;

    mapping(address => uint256) public userPurchaseCount;
    mapping(uint256 => uint256) public itemPurchaseCount;
    mapping(address => mapping(uint256 => uint256)) public userItemPurchases; // user => itemId => quantity

    event ItemAdded(
        uint256 indexed itemId,
        string name,
        uint256 price,
        ItemType itemType,
        uint256 indexed timestamp
    );

    event ItemUpdated(
        uint256 indexed itemId,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 indexed timestamp
    );

    event ItemToggled(
        uint256 indexed itemId,
        bool active,
        uint256 indexed timestamp
    );

    event ItemPurchased(
        address indexed buyer,
        uint256 indexed itemId,
        uint256 price,
        ItemType itemType,
        uint256 indexed timestamp
    );

    event MembershipPurchased(
        address indexed buyer,
        MembershipTier tier,
        uint256 purchasedAt,
        uint256 expiresAt,
        uint256 indexed timestamp
    );

    event MembershipUpgraded(
        address indexed user,
        MembershipTier oldTier,
        MembershipTier newTier,
        uint256 indexed timestamp
    );

    event BoostActivated(
        address indexed user,
        BoostType boostType,
        uint256 activatedAt,
        uint256 expiresAt,
        uint256 remainingUses,
        uint256 indexed timestamp
    );

    event BoostConsumed(
        address indexed user,
        BoostType boostType,
        uint256 remainingUses,
        uint256 indexed timestamp
    );

    event BoostExpiredEvent(
        address indexed user,
        BoostType boostType,
        uint256 indexed timestamp
    );

    event AdminWithdraw(
        address indexed admin,
        uint256 amount,
        uint256 contractBalance,
        uint256 indexed timestamp
    );

    event BalanceUpdated(
        address indexed user,
        uint256 oldBalance,
        uint256 newBalance,
        uint256 indexed timestamp
    );

    event UserRegistered(
        address indexed user,
        uint256 indexed timestamp,
        uint256 userIndex
    );

    event MembershipExpired(
        address indexed user,
        MembershipTier tier,
        uint256 indexed timestamp
    );

    event HiLoContractUpdated(
        address indexed oldContract,
        address indexed newContract,
        uint256 indexed timestamp
    );

    event ItemSupplyUpdated(
        uint256 indexed itemId,
        uint256 oldSupply,
        uint256 newSupply,
        uint256 indexed timestamp
    );

    event PaymentTokenAdded(
        address indexed tokenAddress,
        string symbol,
        uint256 indexed timestamp
    );

    event PaymentTokenRemoved(
        address indexed tokenAddress,
        uint256 indexed timestamp
    );

    event TokenWithdraw(
        address indexed user,
        address indexed tokenAddress,
        uint256 amount,
        uint256 newBalance,
        uint256 indexed timestamp
    );

    event UserWithdraw(
        address indexed user,
        uint256 amount,
        uint256 newBalance,
        uint256 indexed timestamp
    );

    event BatchPriceUpdated(
        uint256[] itemIds,
        uint256[] newPrices,
        uint256 indexed timestamp
    );

    event ItemPaymentTokenUpdated(
        uint256 indexed itemId,
        address oldToken,
        address newToken,
        uint256 indexed timestamp
    );

    event ExtraCreditsPurchased(
        address indexed user,
        uint256 amount,
        uint256 totalCredits,
        uint256 indexed timestamp
    );

    event ExtraCreditsConsumed(
        address indexed user,
        uint256 amount,
        uint256 remainingCredits,
        uint256 indexed timestamp
    );

    event BurnItPurchased(
        address indexed user,
        uint256 amount,
        uint256 totalCredits,
        uint256 indexed timestamp
    );

    event BurnItConsumed(
        address indexed user,
        uint256 amount,
        uint256 remainingCredits,
        uint256 indexed timestamp
    );

    event BattleEmojiPurchased(
        address indexed user,
        uint256 indexed itemId,
        uint256 indexed timestamp
    );

    event BattleEmojiConsumed(
        address indexed user,
        uint256 indexed itemId,
        uint256 remainingQuantity,
        uint256 indexed timestamp
    );

    event ItemBoostDurationUpdated(
        uint256 indexed itemId,
        uint256 oldDuration,
        uint256 newDuration,
        uint256 indexed timestamp
    );

    event StreakProtectionActivated(
        address indexed user,
        uint256 indexed timestamp
    );

    event MultiplierBoostActivated(
        address indexed user,
        uint256 multiplier,
        uint256 expiresAt,
        uint256 indexed timestamp
    );

    event BaseURIUpdated(string newBaseURI, uint256 indexed timestamp);

    constructor(address _hiLoContract) Ownable(msg.sender) {
        if (_hiLoContract == address(0)) {
            revert InvalidAddress();
        }
        hiLoContract = IHiLo(_hiLoContract);
        itemCounter = 0;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
        _pause(); // Start paused for safety

        PaymentTokenInfo memory ethToken = PaymentTokenInfo({
            tokenAddress: address(0),
            allowed: true,
            symbol: "ETH",
            decimals: 18
        });
        paymentTokens[address(0)] = ethToken;
        isPaymentToken[address(0)] = true;
        allowedPaymentTokens.push(address(0));
    }

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
        emit BaseURIUpdated(_baseURI, block.timestamp);
    }

    function tokenURI(uint256 _itemId) external view returns (string memory) {
        MarketplaceItem memory item = items[_itemId];
        if (item.id == 0) {
            revert ItemDoesNotExist();
        }
        // If item has a specific metadataURI, use it; otherwise use baseURI + itemId
        if (bytes(item.metadataURI).length > 0) {
            return item.metadataURI;
        }
        // Fallback to baseURI + itemId + ".json"
        // Example: "https://CardWars.s3.amazonaws.com/metadata/1.json"
        return string(abi.encodePacked(baseURI, _toString(_itemId), ".json"));
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function setHiLoContract(address _hiLoContract) external onlyOwner {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (_hiLoContract == address(0)) {
            revert InvalidAddress();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        address oldContract = address(hiLoContract);
        hiLoContract = IHiLo(_hiLoContract);
        ctx.completeEffects();

        ctx.requireInteractions();
        emit HiLoContractUpdated(oldContract, _hiLoContract, block.timestamp);
        _trackEvent(
            msg.sender,
            "HiLoContractUpdated",
            abi.encode(oldContract, _hiLoContract)
        );
    }

    function addPaymentToken(
        address _tokenAddress,
        string memory _symbol,
        uint8 _decimals
    ) external onlyOwner {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (_tokenAddress == address(0)) {
            revert InvalidTokenAddress();
        }
        if (isPaymentToken[_tokenAddress]) {
            revert TokenAlreadyExists();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        PaymentTokenInfo memory tokenInfo = PaymentTokenInfo({
            tokenAddress: _tokenAddress,
            allowed: true,
            symbol: _symbol,
            decimals: _decimals
        });
        paymentTokens[_tokenAddress] = tokenInfo;
        isPaymentToken[_tokenAddress] = true;
        allowedPaymentTokens.push(_tokenAddress);
        ctx.completeEffects();

        ctx.requireInteractions();
        emit PaymentTokenAdded(_tokenAddress, _symbol, block.timestamp);
        _trackEvent(
            msg.sender,
            "PaymentTokenAdded",
            abi.encode(_tokenAddress, _symbol)
        );
    }

    function removePaymentToken(address _tokenAddress) external onlyOwner {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (_tokenAddress == address(0)) {
            revert InvalidTokenAddress();
        }
        if (!isPaymentToken[_tokenAddress]) {
            revert TokenNotAllowed();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        paymentTokens[_tokenAddress].allowed = false;
        ctx.completeEffects();

        ctx.requireInteractions();
        emit PaymentTokenRemoved(_tokenAddress, block.timestamp);
        _trackEvent(
            msg.sender,
            "PaymentTokenRemoved",
            abi.encode(_tokenAddress)
        );
    }

    function addItem(
        string memory _name,
        string memory _description,
        uint256 _price,
        address _paymentToken,
        ItemType _itemType,
        MembershipTier _membershipTier,
        BoostType _boostType,
        uint256 _boostDuration,
        string memory _metadataURI,
        uint256 _supply
    ) external onlyOwner returns (uint256) {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (!isPaymentToken[_paymentToken]) {
            revert TokenNotAllowed();
        }
        if (!paymentTokens[_paymentToken].allowed) {
            revert TokenNotAllowed();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        itemCounter++;
        PaymentToken paymentTokenType = _paymentToken == address(0)
            ? PaymentToken.ETH
            : PaymentToken.ERC20;

        items[itemCounter] = MarketplaceItem({
            id: itemCounter,
            name: _name,
            description: _description,
            price: _price,
            paymentToken: _paymentToken,
            paymentTokenType: paymentTokenType,
            itemType: _itemType,
            membershipTier: _membershipTier,
            boostType: _boostType,
            boostDuration: _boostDuration,
            metadataURI: _metadataURI,
            active: true,
            supply: _supply,
            sold: 0
        });

        unchecked {
            totalItemsAdded++;
        }
        ctx.completeEffects();

        ctx.requireInteractions();
        uint256 newItemId = itemCounter;
        emit ItemAdded(newItemId, _name, _price, _itemType, block.timestamp);
        _trackEvent(
            msg.sender,
            "ItemAdded",
            abi.encode(newItemId, _name, _price, uint8(_itemType))
        );
        return newItemId;
    }

    function updateItemPrice(
        uint256 _itemId,
        uint256 _newPrice
    ) external onlyOwner {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (items[_itemId].id == 0) {
            revert ItemDoesNotExist();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        uint256 oldPrice = items[_itemId].price;
        items[_itemId].price = _newPrice;
        ctx.completeEffects();

        ctx.requireInteractions();
        emit ItemUpdated(_itemId, oldPrice, _newPrice, block.timestamp);
        _trackEvent(
            msg.sender,
            "ItemPriceUpdated",
            abi.encode(_itemId, oldPrice, _newPrice)
        );
    }

    function updateItemPaymentToken(
        uint256 _itemId,
        address _newPaymentToken
    ) external onlyOwner {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (items[_itemId].id == 0) {
            revert ItemDoesNotExist();
        }
        if (
            !isPaymentToken[_newPaymentToken] ||
            !paymentTokens[_newPaymentToken].allowed
        ) {
            revert TokenNotAllowed();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        address oldToken = items[_itemId].paymentToken;
        items[_itemId].paymentToken = _newPaymentToken;
        items[_itemId].paymentTokenType = _newPaymentToken == address(0)
            ? PaymentToken.ETH
            : PaymentToken.ERC20;
        ctx.completeEffects();

        ctx.requireInteractions();
        emit ItemPaymentTokenUpdated(
            _itemId,
            oldToken,
            _newPaymentToken,
            block.timestamp
        );
        _trackEvent(
            msg.sender,
            "ItemPaymentTokenUpdated",
            abi.encode(_itemId, oldToken, _newPaymentToken)
        );
    }

    function batchUpdatePrices(
        uint256[] memory _itemIds,
        uint256[] memory _newPrices
    ) external onlyOwner {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (_itemIds.length != _newPrices.length || _itemIds.length == 0) {
            revert InvalidBatchSize();
        }
        for (uint256 i = 0; i < _itemIds.length; i++) {
            if (items[_itemIds[i]].id == 0) {
                revert ItemDoesNotExist();
            }
        }
        ctx.completeChecks();

        ctx.requireEffects();
        for (uint256 i = 0; i < _itemIds.length; i++) {
            items[_itemIds[i]].price = _newPrices[i];
        }
        ctx.completeEffects();

        ctx.requireInteractions();
        emit BatchPriceUpdated(_itemIds, _newPrices, block.timestamp);
        _trackEvent(
            msg.sender,
            "BatchPriceUpdated",
            abi.encode(_itemIds, _newPrices)
        );
    }

    function toggleItemActive(uint256 _itemId) external onlyOwner {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (items[_itemId].id == 0) {
            revert ItemDoesNotExist();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        bool newActive = !items[_itemId].active;
        items[_itemId].active = newActive;
        ctx.completeEffects();

        ctx.requireInteractions();
        emit ItemToggled(_itemId, newActive, block.timestamp);
        _trackEvent(msg.sender, "ItemToggled", abi.encode(_itemId, newActive));
    }

    function updateItemSupply(
        uint256 _itemId,
        uint256 _newSupply
    ) external onlyOwner {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (items[_itemId].id == 0) {
            revert ItemDoesNotExist();
        }
        if (_newSupply < items[_itemId].sold) {
            revert InvalidAmount();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        uint256 oldSupply = items[_itemId].supply;
        items[_itemId].supply = _newSupply;
        ctx.completeEffects();

        ctx.requireInteractions();
        emit ItemSupplyUpdated(_itemId, oldSupply, _newSupply, block.timestamp);
        _trackEvent(
            msg.sender,
            "ItemSupplyUpdated",
            abi.encode(_itemId, oldSupply, _newSupply)
        );
    }

    function updateItemBoostDuration(
        uint256 _itemId,
        uint256 _newDuration
    ) external onlyOwner {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (items[_itemId].id == 0) {
            revert ItemDoesNotExist();
        }
        if (items[_itemId].itemType != ItemType.Boost) {
            revert InvalidItemType();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        uint256 oldDuration = items[_itemId].boostDuration;
        items[_itemId].boostDuration = _newDuration;
        ctx.completeEffects();

        ctx.requireInteractions();
        emit ItemBoostDurationUpdated(
            _itemId,
            oldDuration,
            _newDuration,
            block.timestamp
        );
        _trackEvent(
            msg.sender,
            "ItemBoostDurationUpdated",
            abi.encode(_itemId, oldDuration, _newDuration)
        );
    }

    function purchaseItem(
        uint256 _itemId
    ) external payable nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        MarketplaceItem storage item = items[_itemId];

        ctx.requireChecks();
        if (item.id == 0) {
            revert ItemDoesNotExist();
        }
        if (!item.active) {
            revert ItemNotActive();
        }
        // If supply is 0, it means unlimited supply
        if (item.supply > 0 && item.sold >= item.supply) {
            revert ItemSoldOut();
        }

        if (item.paymentTokenType == PaymentToken.ETH) {
            if (msg.value != item.price) {
                revert InvalidAmount();
            }
        } else {
            if (msg.value != 0) {
                revert MustNotSendETH();
            }
            IERC20 token = IERC20(item.paymentToken);
            if (token.balanceOf(msg.sender) < item.price) {
                revert InsufficientTokenBalance();
            }
        }
        ctx.completeChecks();

        ctx.requireEffects();

        // Cache item values to reduce storage reads
        ItemType cachedItemType = item.itemType;
        PaymentToken cachedPaymentTokenType = item.paymentTokenType;
        address cachedPaymentToken = item.paymentToken;
        uint256 cachedPrice = item.price;
        MembershipTier cachedMembershipTier = item.membershipTier;
        BoostType cachedBoostType = item.boostType;
        uint256 cachedBoostDuration = item.boostDuration;

        if (cachedPaymentTokenType == PaymentToken.ERC20) {
            // Transfer tokens from user to contract using SafeERC20
            IERC20 token = IERC20(cachedPaymentToken);
            token.safeTransferFrom(msg.sender, address(this), cachedPrice);
        }
        // ETH payment is already received via msg.value
        unchecked {
            item.sold++;
            totalPurchases++;
            userPurchaseCount[msg.sender]++;
            itemPurchaseCount[_itemId]++;
            userItemPurchases[msg.sender][_itemId]++;
        }

        bool isNewUser = !isUser[msg.sender];
        if (isNewUser) {
            isUser[msg.sender] = true;
            userIndex[msg.sender] = allUsers.length;
            allUsers.push(msg.sender);
        }

        if (cachedItemType == ItemType.Membership) {
            MembershipTier oldTier = memberships[msg.sender].tier;
            _activateMembership(msg.sender, cachedMembershipTier);
            if (oldTier < cachedMembershipTier) {
                emit MembershipUpgraded(
                    msg.sender,
                    oldTier,
                    cachedMembershipTier,
                    block.timestamp
                );
            }
        } else if (cachedItemType == ItemType.Boost) {
            // Boost can always be purchased - uses are added to existing boost
            _activateBoost(msg.sender, cachedBoostType, cachedBoostDuration);
        } else if (cachedItemType == ItemType.ExtraCredits) {
            // Extra credits can always be purchased - credits are added
            extraCredits[msg.sender] += Constants.EXTRA_CREDITS_AMOUNT;
            emit ExtraCreditsPurchased(
                msg.sender,
                Constants.EXTRA_CREDITS_AMOUNT,
                extraCredits[msg.sender],
                block.timestamp
            );
        } else if (cachedItemType == ItemType.BurnIt) {
            // Burn It: Skip card, auto correct guess (1 item = 1 guess)
            burnItCredits[msg.sender] += 1;
            emit BurnItPurchased(
                msg.sender,
                1,
                burnItCredits[msg.sender],
                block.timestamp
            );
        } else if (cachedItemType == ItemType.BattleEmoji) {
            // Battle Emoji: Animated emoji to send to opponent after battle
            // Emojis are consumable - once used, they are consumed
            userBattleEmojis[msg.sender][_itemId] += 1;
            emit BattleEmojiPurchased(msg.sender, _itemId, block.timestamp);
        } else if (cachedItemType == ItemType.StreakProtection) {
            // Streak protection: Prevents next loss from breaking streak
            streakProtection[msg.sender] = true;
            emit StreakProtectionActivated(msg.sender, block.timestamp);
        } else if (item.itemType == ItemType.MultiplierBoost) {
            // Multiplier boost: Temporary multiplier (stored in boostDuration field)
            uint256 multiplier = item.boostDuration; // Reuse boostDuration field for multiplier value
            uint256 duration = 1 hours; // Default 1 hour, can be customized per item
            multiplierBoost[msg.sender] = multiplier;
            multiplierBoostExpires[msg.sender] = block.timestamp + duration;
            emit MultiplierBoostActivated(
                msg.sender,
                multiplier,
                block.timestamp + duration,
                block.timestamp
            );
        }
        ctx.completeEffects();

        ctx.requireInteractions();
        if (isNewUser) {
            emit UserRegistered(
                msg.sender,
                block.timestamp,
                userIndex[msg.sender]
            );
        }

        if (item.itemType == ItemType.Membership) {
            emit MembershipPurchased(
                msg.sender,
                item.membershipTier,
                block.timestamp,
                block.timestamp + Constants.MEMBERSHIP_DURATION,
                block.timestamp
            );
        } else if (item.itemType == ItemType.Boost) {
            emit BoostActivated(
                msg.sender,
                item.boostType,
                block.timestamp,
                block.timestamp + item.boostDuration,
                Constants.TX_BOOST_BATCH_SIZE,
                block.timestamp
            );
        }

        emit ItemPurchased(
            msg.sender,
            _itemId,
            item.price,
            item.itemType,
            block.timestamp
        );

        // Events for payment tracking (no balance tracking needed for direct payment)

        _trackEvent(
            msg.sender,
            "ItemPurchased",
            abi.encode(
                _itemId,
                item.price,
                uint8(item.itemType),
                item.paymentToken
            )
        );
    }

    function _activateMembership(address _user, MembershipTier _tier) internal {
        UserMembership storage membership = memberships[_user];
        uint64 currentTime = uint64(block.timestamp);
        uint64 additionalDuration = uint64(Constants.MEMBERSHIP_DURATION);

        // If membership expired or tier is lower, start new membership
        if (membership.expiresAt < currentTime || membership.tier < _tier) {
            membership.tier = _tier;
            membership.purchasedAt = currentTime;
            membership.expiresAt = currentTime + additionalDuration;
        } else if (_tier > membership.tier) {
            // Upgrade to higher tier - reset duration from now
            membership.tier = _tier;
            membership.purchasedAt = currentTime;
            membership.expiresAt = currentTime + additionalDuration;
        } else if (_tier == membership.tier) {
            // Same tier - extend duration from current expiry (or now if expired)
            uint64 newExpiry = membership.expiresAt < currentTime
                ? currentTime + additionalDuration
                : membership.expiresAt + additionalDuration;
            membership.expiresAt = newExpiry;
            // Update purchasedAt only if extending from expired state
            if (membership.expiresAt < currentTime) {
                membership.purchasedAt = currentTime;
            }
        }
    }

    function _activateBoost(
        address _user,
        BoostType _boostType,
        uint256 _duration
    ) internal {
        UserBoost storage userBoost = boosts[_user];
        uint64 currentTime = uint64(block.timestamp);
        uint64 expiryTime = uint64(block.timestamp + _duration);

        if (
            userBoost.expiresAt < currentTime ||
            userBoost.boostType != _boostType
        ) {
            userBoost.boostType = _boostType;
            userBoost.activatedAt = currentTime;
            userBoost.expiresAt = expiryTime;
            userBoost.remainingUses = Constants.TX_BOOST_BATCH_SIZE;
        } else {
            userBoost.remainingUses += Constants.TX_BOOST_BATCH_SIZE;
            if (userBoost.expiresAt < expiryTime) {
                userBoost.expiresAt = expiryTime;
            }
        }
    }

    function consumeBoost(
        address _user
    ) external override nonReentrant returns (bool) {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (msg.sender != address(hiLoContract)) {
            revert Unauthorized();
        }

        UserBoost storage userBoost = boosts[_user];

        if (userBoost.boostType == BoostType.None) {
            return false;
        }

        if (userBoost.expiresAt < block.timestamp) {
            ctx.completeChecks();
            ctx.requireEffects();
            userBoost.boostType = BoostType.None;
            ctx.completeEffects();
            ctx.requireInteractions();
            emit BoostExpiredEvent(_user, userBoost.boostType, block.timestamp);
            _trackEvent(
                _user,
                "BoostExpired",
                abi.encode(uint8(userBoost.boostType))
            );
            return false;
        }

        if (userBoost.remainingUses == 0) {
            revert NoRemainingUses();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        unchecked {
            userBoost.remainingUses--;
        }
        ctx.completeEffects();

        ctx.requireInteractions();
        emit BoostConsumed(
            _user,
            userBoost.boostType,
            userBoost.remainingUses,
            block.timestamp
        );
        _trackEvent(
            _user,
            "BoostConsumed",
            abi.encode(uint8(userBoost.boostType), userBoost.remainingUses)
        );
        return true;
    }

    function adminWithdraw(uint256 _amount) external onlyOwner nonReentrant {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (address(this).balance < _amount) {
            revert InsufficientContractBalance();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        uint256 contractBalance = address(this).balance;
        ctx.completeEffects();

        ctx.requireInteractions();
        (bool success, ) = payable(owner()).call{value: _amount}("");
        if (!success) {
            revert TokenTransferFailed();
        }

        emit AdminWithdraw(
            owner(),
            _amount,
            address(this).balance,
            block.timestamp
        );
        _trackEvent(
            msg.sender,
            "AdminWithdraw",
            abi.encode(_amount, contractBalance)
        );
    }

    function adminWithdrawToken(
        address _tokenAddress,
        uint256 _amount
    ) external onlyOwner nonReentrant {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (_tokenAddress == address(0)) {
            revert InvalidTokenAddress();
        }
        IERC20 token = IERC20(_tokenAddress);
        if (token.balanceOf(address(this)) < _amount) {
            revert InsufficientContractBalance();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        uint256 contractBalance = token.balanceOf(address(this));
        ctx.completeEffects();

        ctx.requireInteractions();
        token.safeTransfer(owner(), _amount);

        emit AdminWithdraw(
            owner(),
            _amount,
            token.balanceOf(address(this)),
            block.timestamp
        );
        _trackEvent(
            msg.sender,
            "AdminWithdrawToken",
            abi.encode(_tokenAddress, _amount, contractBalance)
        );
    }

    function getUserMembership(
        address _user
    ) external view override returns (MembershipTier, uint256, uint256) {
        UserMembership memory membership = memberships[_user];
        if (membership.expiresAt < block.timestamp) {
            return (MembershipTier.Basic, 0, 0);
        }
        return (
            membership.tier,
            uint256(membership.purchasedAt),
            uint256(membership.expiresAt)
        );
    }

    function getMultiplierBoost(
        address _user
    ) external view override returns (uint256 multiplier, uint256 expiresAt) {
        uint256 boost = multiplierBoost[_user];
        uint256 expiry = multiplierBoostExpires[_user];

        // Return boost only if it's active (non-zero and not expired)
        if (boost > 0 && expiry > block.timestamp) {
            return (boost, expiry);
        }

        return (0, 0);
    }

    function getUserBoost(
        address _user
    ) external view override returns (ActiveBoost memory) {
        UserBoost memory userBoost = boosts[_user];
        if (
            userBoost.expiresAt < block.timestamp ||
            userBoost.boostType == BoostType.None
        ) {
            return
                ActiveBoost({
                    boostType: BoostType.None,
                    expiresAt: 0,
                    remainingUses: 0
                });
        }
        return
            ActiveBoost({
                boostType: userBoost.boostType,
                expiresAt: userBoost.expiresAt,
                remainingUses: userBoost.remainingUses
            });
    }

    function getItem(
        uint256 _itemId
    ) external view returns (MarketplaceItem memory) {
        return items[_itemId];
    }

    function getUserBalance(
        address /* _user */
    ) external pure returns (uint256) {
        return 0; // Users don't have balances anymore - direct payment only
    }

    function getUserExtraCredits(
        address _user
    ) external view returns (uint256) {
        return extraCredits[_user];
    }

    function getUserBurnItCredits(
        address _user
    ) external view returns (uint256) {
        return burnItCredits[_user];
    }

    function hasBattleEmoji(
        address _user,
        uint256 _emojiItemId
    ) external view returns (bool) {
        return userBattleEmojis[_user][_emojiItemId] > 0;
    }

    function getBattleEmojiQuantity(
        address _user,
        uint256 _emojiItemId
    ) external view returns (uint256) {
        return userBattleEmojis[_user][_emojiItemId];
    }

    function getUserItemPurchaseCount(
        address _user,
        uint256 _itemId
    ) external view returns (uint256) {
        return userItemPurchases[_user][_itemId];
    }

    function consumeBattleEmoji(
        address _user,
        uint256 _emojiItemId
    ) external nonReentrant returns (bool) {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (msg.sender != battleContract) {
            revert Unauthorized();
        }
        if (userBattleEmojis[_user][_emojiItemId] == 0) {
            return false;
        }
        ctx.completeChecks();

        ctx.requireEffects();
        userBattleEmojis[_user][_emojiItemId] -= 1;
        ctx.completeEffects();

        ctx.requireInteractions();
        emit BattleEmojiConsumed(
            _user,
            _emojiItemId,
            userBattleEmojis[_user][_emojiItemId],
            block.timestamp
        );
        _trackEvent(
            _user,
            "BattleEmojiConsumed",
            abi.encode(_emojiItemId, userBattleEmojis[_user][_emojiItemId])
        );
        return true;
    }

    function consumeExtraCredits(
        address _user,
        uint256 _amount
    ) external nonReentrant returns (bool) {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (msg.sender != address(hiLoContract)) {
            revert Unauthorized();
        }
        if (extraCredits[_user] < _amount) {
            return false;
        }
        ctx.completeChecks();

        ctx.requireEffects();
        extraCredits[_user] -= _amount;
        ctx.completeEffects();

        ctx.requireInteractions();
        emit ExtraCreditsConsumed(
            _user,
            _amount,
            extraCredits[_user],
            block.timestamp
        );
        _trackEvent(
            _user,
            "ExtraCreditsConsumed",
            abi.encode(_amount, extraCredits[_user])
        );
        return true;
    }

    function consumeBurnIt(
        address _user,
        uint256 _amount
    ) external nonReentrant returns (bool) {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (msg.sender != address(hiLoContract)) {
            revert Unauthorized();
        }
        if (burnItCredits[_user] < _amount) {
            return false;
        }
        ctx.completeChecks();

        ctx.requireEffects();
        burnItCredits[_user] -= _amount;
        ctx.completeEffects();

        ctx.requireInteractions();
        emit BurnItConsumed(
            _user,
            _amount,
            burnItCredits[_user],
            block.timestamp
        );
        _trackEvent(
            _user,
            "BurnItConsumed",
            abi.encode(_amount, burnItCredits[_user])
        );
        return true;
    }

    function getUserCount() external view returns (uint256) {
        return allUsers.length;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getUserAddress(uint256 index) external view returns (address) {
        if (index >= allUsers.length) {
            revert InvalidAddress();
        }
        return allUsers[index];
    }

    function checkMembershipExpiry(address _user) external {
        UserMembership storage membership = memberships[_user];
        if (
            membership.expiresAt < block.timestamp &&
            membership.tier != MembershipTier.Basic
        ) {
            MembershipTier expiredTier = membership.tier;
            membership.tier = MembershipTier.Basic;
            emit MembershipExpired(_user, expiredTier, block.timestamp);
            _trackEvent(
                _user,
                "MembershipExpired",
                abi.encode(uint8(expiredTier))
            );
        }
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

    function getTotalItemsAdded() external view returns (uint256) {
        return totalItemsAdded;
    }

    function getTotalPurchases() external view returns (uint256) {
        return totalPurchases;
    }

    function getUserPurchaseCount(
        address user
    ) external view returns (uint256) {
        return userPurchaseCount[user];
    }

    function getItemPurchaseCount(
        uint256 itemId
    ) external view returns (uint256) {
        return itemPurchaseCount[itemId];
    }

    function getUserTokenBalance(
        address /* user */,
        address /* tokenAddress */
    ) external pure returns (uint256) {
        // Users don't have balances anymore - direct payment only
        return 0;
    }

    function getAllowedPaymentTokens()
        external
        view
        returns (address[] memory)
    {
        return allowedPaymentTokens;
    }

    function getPaymentTokenInfo(
        address tokenAddress
    ) external view returns (PaymentTokenInfo memory) {
        return paymentTokens[tokenAddress];
    }

    function isTokenAllowed(address tokenAddress) external view returns (bool) {
        return
            isPaymentToken[tokenAddress] && paymentTokens[tokenAddress].allowed;
    }

    function setBattleContract(address _battleContract) external onlyOwner {
        if (_battleContract == address(0)) {
            revert InvalidAddress();
        }
        battleContract = _battleContract;
    }

    function getUsersWithMembership(
        uint8 tier
    ) external view returns (address[] memory addresses, uint8[] memory tiers) {
        address[] memory usersWithMembership = new address[](allUsers.length);
        uint8[] memory membershipTiers = new uint8[](allUsers.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allUsers.length; i++) {
            UserMembership memory membership = memberships[allUsers[i]];
            if (
                uint8(membership.tier) == tier &&
                membership.expiresAt > uint64(block.timestamp)
            ) {
                usersWithMembership[count] = allUsers[i];
                membershipTiers[count] = uint8(membership.tier);
                count++;
            }
        }

        addresses = new address[](count);
        tiers = new uint8[](count);
        for (uint256 i = 0; i < count; i++) {
            addresses[i] = usersWithMembership[i];
            tiers[i] = membershipTiers[i];
        }
    }

    function getUsersWithActiveMembership()
        external
        view
        returns (address[] memory)
    {
        address[] memory activeUsers = new address[](allUsers.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allUsers.length; i++) {
            UserMembership memory membership = memberships[allUsers[i]];
            if (
                membership.tier != MembershipTier.Basic &&
                membership.expiresAt > uint64(block.timestamp)
            ) {
                activeUsers[count] = allUsers[i];
                count++;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = activeUsers[i];
        }
        return result;
    }

    function getTopPurchasers(
        uint256 limit
    )
        external
        view
        returns (address[] memory addresses, uint256[] memory purchaseCounts)
    {
        address[] memory sortedUsers = new address[](allUsers.length);
        uint256[] memory counts = new uint256[](allUsers.length);

        for (uint256 i = 0; i < allUsers.length; i++) {
            sortedUsers[i] = allUsers[i];
            counts[i] = userPurchaseCount[allUsers[i]];
        }

        uint256 userCount = allUsers.length;
        uint256 resultCount = userCount < limit ? userCount : limit;

        for (uint256 i = 0; i < resultCount; i++) {
            uint256 maxIndex = i;
            for (uint256 j = i + 1; j < userCount; j++) {
                if (counts[j] > counts[maxIndex]) {
                    maxIndex = j;
                }
            }
            if (maxIndex != i) {
                address tempAddr = sortedUsers[i];
                uint256 tempCount = counts[i];
                sortedUsers[i] = sortedUsers[maxIndex];
                counts[i] = counts[maxIndex];
                sortedUsers[maxIndex] = tempAddr;
                counts[maxIndex] = tempCount;
            }
        }

        addresses = new address[](resultCount);
        purchaseCounts = new uint256[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            addresses[i] = sortedUsers[i];
            purchaseCounts[i] = counts[i];
        }
    }

    function getUsersByItemPurchase(
        uint256 itemId,
        uint256 minQuantity
    ) external view returns (address[] memory) {
        address[] memory usersWithItem = new address[](allUsers.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allUsers.length; i++) {
            uint256 quantity = userItemPurchases[allUsers[i]][itemId];
            if (quantity >= minQuantity) {
                usersWithItem[count] = allUsers[i];
                count++;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = usersWithItem[i];
        }
        return result;
    }

    function getUsersWithBoost() external view returns (address[] memory) {
        address[] memory usersWithBoost = new address[](allUsers.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allUsers.length; i++) {
            UserBoost memory boost = boosts[allUsers[i]];
            if (
                boost.boostType != BoostType.None &&
                boost.expiresAt > uint64(block.timestamp) &&
                boost.remainingUses > 0
            ) {
                usersWithBoost[count] = allUsers[i];
                count++;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = usersWithBoost[i];
        }
        return result;
    }
}
