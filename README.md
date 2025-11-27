# CardWars Smart Contracts

Smart contracts for the CardWars blockchain card battle game. This repository contains all on-chain game logic including Hi-Lo gameplay, marketplace, battle system, clan management, and profile management.

## 📋 Table of Contents

- [Overview](#overview)
- [Contracts](#contracts)
- [Features](#features)
- [Setup](#setup)
- [Deployment](#deployment)
- [Testing](#testing)
- [Documentation](#documentation)
- [Network Configuration](#network-configuration)
- [Security](#security)

## 🎯 Overview

CardWars is a fully on-chain card prediction game built on Ethereum-compatible networks. The smart contracts handle:

- **Hi-Lo Game Logic**: Card prediction mechanics with SuperGem rewards
- **Marketplace**: Membership tiers, boosts, credits, and cosmetic items
- **Battle System**: 1v1 competitive battles with scoring
- **Clan System**: Team-based gameplay with leaderboards
- **Profile Management**: User profiles with on-chain metadata

## 📦 Contracts

### Core Contracts

#### `CardWarsHiLo.sol`

Main game contract handling Hi-Lo gameplay mechanics.

**Key Features:**

- On-chain game state management
- Card generation with secure randomness
- SuperGem reward calculation
- Membership multiplier integration
- Streak bonus system
- Achievement tracking
- Weekly leaderboard updates
- Batch guess support (with TxBoost)
- Daily free guesses (100 per day)

**Main Functions:**

- `startGame()`: Initialize a new game session
- `makeGuess()`: Make a single prediction
- `batchGuess()`: Make multiple predictions in one transaction (requires TxBoost)
- `resetGame()`: Start fresh with a new card (max 3 per hour)
- `updateClanLeaderboard()`: Refresh weekly clan rankings

#### `CardWarsMarketplace.sol`

Marketplace contract for purchasing memberships, boosts, and items.

**Key Features:**

- Membership tier sales (Basic, Plus, Pro)
- Multiple payment tokens (ETH, ERC20)
- Item management (add, update, toggle)
- Boost system integration
- Metadata URI support
- Supply management
- Admin withdrawal functionality

**Item Types:**

- `Membership`: Plus or Pro - 30 days (paid with ETH or USDT)
- `Boost`: TxBoost for batch mode
- `ExtraCredits`: 100 additional guesses
- `StreakProtection`: Prevents streak from breaking
- `MultiplierBoost`: Temporary multiplier increase
- `BurnIt`: Skip card, auto correct guess
- `BattleEmoji`: Animated emojis for battles
- `ClanCosmetic`: Decorative items for clans

**Main Functions:**

- `purchaseItem()`: Buy marketplace items
- `checkMembershipExpiry()`: Verify and update membership status
- `addItem()`: Add new items (admin only)
- `updateItemPrice()`: Update item prices (admin only)

#### `CardWarsBattle.sol`

Battle system contract for 1v1 competitive gameplay.

**Key Features:**

- 10-round battles
- Queue-based matchmaking
- Invitation system
- Timeout handling (48 hours)
- Turn timeout (48 hours)
- Battle scoring and winner determination
- Emoji system

**Main Functions:**

- `joinQueue()`: Enter random matchmaking queue
- `leaveQueue()`: Exit queue
- `createBattle()`: Challenge specific player
- `findRandomOpponent()`: Instantly find opponent from queue
- `acceptBattle()`: Accept battle invitation
- `rejectBattleInvitation()`: Reject invitation
- `playBattleRound()`: Make predictions in active battles
- `cancelBattle()`: Cancel pending battles
- `sendBattleEmoji()`: Send emojis during battles

#### `CardWarsClan.sol`

Clan management contract for team-based gameplay.

**Key Features:**

- Clan creation (0.00005 ETH fee)
- Maximum 8 members per clan
- Application and invitation systems
- Leadership transfer
- Member management (kick, leave)
- Cosmetic items
- Leaderboard integration

**Main Functions:**

- `createClan()`: Create new clan (paid: 0.00005 ETH)
- `joinClan()`: Join open clan
- `applyToClan()`: Request to join (if approval required)
- `acceptApplication()`: Accept join request (leader only)
- `rejectApplication()`: Reject join request (leader only)
- `acceptInvitation()`: Accept clan invitation
- `rejectInvitation()`: Reject invitation
- `transferLeadership()`: Transfer clan leadership
- `kickMember()`: Remove member (leader only)
- `disbandClan()`: Delete clan (leader only)
- `updateClanSettings()`: Update name, description, approval settings
- `applyCosmetic()`: Apply cosmetic items to clan

#### `CardWarsProfile.sol`

Profile management contract for user metadata.

**Key Features:**

- Display name management
- X (Twitter) handle linking
- Farcaster account linking
- Avatar URL storage
- Public profile viewing
- Profile search functionality

**Main Functions:**

- `updateProfile()`: Update display name, X handle, avatar URL

## ✨ Features

### Membership System

**Tiers:**

- **Basic**: 1x multiplier (free, default)
- **Plus**: 2x multiplier + streak bonuses (30 days, paid with ETH or USDT)
- **Pro**: 3x multiplier + enhanced streak bonuses (30 days, paid with ETH or USDT)

**Streak Bonuses:**

- **Plus**: +1 SuperGem (streak 5+), +3 SuperGem (streak 10+)
- **Pro**: +2 SuperGem (streak 5+), +5 SuperGem (streak 10+)

### SuperGem System

**Base Earnings:**

- Normal win: 1 SuperGem
- Suit win: 5 SuperGems
- Joker win: 100x multiplier

**Calculation Formula:**

```
SuperGem = (BaseSuperGem × MembershipMultiplier) + StreakBonus + AchievementBonus
```

**Achievement Bonuses:**

- 5 correct guesses: +5 SuperGems
- 10 correct guesses: +15 SuperGems
- 20 correct guesses: +50 SuperGems

**Penalties:**

- Wrong Hi-Lo guess: -1 SuperGem
- Wrong suit prediction: -3 SuperGems

### Battle System

**Battle Mechanics:**

- 10 rounds per battle
- 48-hour battle timeout
- 48-hour turn timeout
- Winner determined by highest score
- Battle points contribute to clan leaderboard

### Security Features

- ✅ ReentrancyGuard protection
- ✅ CEI (Checks-Effects-Interactions) pattern
- ✅ Pausable mechanism
- ✅ Access control (Ownable, AccessControl)
- ✅ Input validation
- ✅ SafeERC20 token transfers
- ✅ Custom errors (gas optimization)
- ✅ Overflow protection

## 🚀 Setup

### Prerequisites

- Node.js >= 20.0.0
- npm >= 10.0.0
- Hardhat >= 2.22.0

### Installation

1. **Install dependencies:**

```bash
npm install
```

2. **Create `.env` file:**

```env
# Required
PRIVATE_KEY=your_private_key_here

# Optional (for verification)
ETHERSCAN_API_KEY=your_etherscan_api_key
COINGECKO_API_KEY=your_coingecko_api_key

# Network RPC URLs (optional, defaults provided)
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
```

3. **Compile contracts:**

```bash
npm run compile
```

4. **Generate TypeScript types:**

```bash
npm run typechain
```

## 📤 Deployment

### Deploy to Sepolia Testnet

```bash
npm run deploy --network sepolia
```

### Deploy to Soneium Minato Testnet

```bash
npm run deploy:minato
```

### Deploy to BNB Testnet

```bash
npm run deploy:bnb
```

### Deploy to Local Hardhat Network

```bash
npm run deploy:local
```

### Verify Contracts

**Sepolia:**

```bash
npx hardhat verify --network sepolia <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS>
```

**Soneium Minato:**

```bash
npm run verify:minato
```

**BNB Testnet:**

```bash
npm run verify:bnb
```

### Deployment Scripts

- `scripts/deploy.ts`: Deploy all contracts
- `scripts/deploy-clan-only.ts`: Deploy only Clan contract
- `scripts/deploy-marketplace-only.ts`: Deploy only Marketplace contract
- `scripts/deploy-mock-usdt.ts`: Deploy MockUSDT for testing

## 🧪 Testing

Run tests:

```bash
npm test
```

Test files:

- `test/RandomLib.test.ts`: Random number generation tests
- `test/DeerCard.test.ts`: Deer card functionality tests

## 📚 Documentation

### Contract Documentation

- **[CONTRACTS_OVERVIEW.md](./docs/CONTRACTS_OVERVIEW.md)**: Overview of all contracts
- **[MEMBERSHIP_BENEFITS.md](./docs/MEMBERSHIP_BENEFITS.md)**: Detailed membership benefits
- **[BATTLE_SYSTEM.md](./docs/BATTLE_SYSTEM.md)**: Battle system mechanics
- **[CLAN_SYSTEM.md](./docs/CLAN_SYSTEM.md)**: Clan system details
- **[BOOST_SYSTEM.md](./docs/BOOST_SYSTEM.md)**: Boost system explanation
- **[MARKETPLACE_ITEMS_AND_METADATA.md](./docs/MARKETPLACE_ITEMS_AND_METADATA.md)**: Marketplace items guide
- **[ADMIN_CAPABILITIES.md](./docs/ADMIN_CAPABILITIES.md)**: Admin functions guide
- **[EVENTS_INDEXING.md](./docs/EVENTS_INDEXING.md)**: Event indexing guide
- **[LEADERBOARD_DATA.md](./docs/LEADERBOARD_DATA.md)**: Leaderboard data structure

### PDF Documentation

- **[CardWars_Technical_Documentation.pdf](./docs/CardWars_Technical_Documentation.pdf)**: Complete technical documentation
- **[CardWars_User_Guide.pdf](./docs/CardWars_User_Guide.pdf)**: User guide
- **[CardWars_Scoring_System.pdf](./docs/CardWars_Scoring_System.pdf)**: Scoring system details
- **[CardWars_SuperGem_Tutorial.pdf](./docs/CardWars_SuperGem_Tutorial.pdf)**: SuperGem earnings guide
- **[CardWars_Transaction_Guide.pdf](./docs/CardWars_Transaction_Guide.pdf)**: Transaction guide

## 🌐 Network Configuration

### Supported Networks

| Network         | Chain ID | RPC URL                                         | Status         |
| --------------- | -------- | ----------------------------------------------- | -------------- |
| Sepolia         | 11155111 | Various                                         | ✅ Active      |
| Soneium Minato  | 1946     | https://rpc.minato.soneium.org/                 | ✅ Active      |
| Soneium Mainnet | 1868     | https://rpc.soneium.org/                        | ✅ Ready       |
| BNB Testnet     | 97       | https://data-seed-prebsc-1-s1.binance.org:8545/ | ✅ Active      |
| Hardhat Local   | 1337     | http://127.0.0.1:8545                           | ✅ Development |

### Deployment Addresses

#### Sepolia Testnet

- **CardWarsHiLo**: `0xff786954832A3DC4C1E9deb95bB3fbC88c6323Fa`
- **CardWarsMarketplace**: `0x63D3f5d2cf7dc874E491e52C789Ce22C69321b1b`
- **CardWarsBattle**: `0x2b093F923f6146CdBdaFf6DA6dDe4AeeDdFd7250`
- **CardWarsClan**: `0x9697a01b84306072A1D3B231444FB1B35494559d`
- **CardWarsProfile**: `0x31599B76946D45Ff5C8E53c19e388cc13d558E53`
- **MockUSDT**: `0x02C0E9a9827b2220Bc89cB6a3B6F85bfdABDdA2a`

#### Soneium Minato Testnet

- **CardWarsHiLo**: `0xA80Ea1cca37688F49d9F24285b7157F5d25516fE`
- **CardWarsMarketplace**: `0x5BA7480bab01ca323141C0A6a790695a3E28d652`
- **CardWarsBattle**: `0x0Dd00165DC12897B702963ae3a23c5C2d474742B`
- **CardWarsClan**: `0xB70178999E3cebDDb90655687E46c01866418086`
- **CardWarsProfile**: `0x8926d1A6c1FD37c79E4e7065E4d095a6e8716d52`

## 🔧 Admin Functions

### Marketplace Admin

- `addItem()`: Add new marketplace items
- `updateItemPrice()`: Update item prices
- `updateItemPaymentToken()`: Change payment token
- `updateItemSupply()`: Update item supply
- `toggleItemActive()`: Enable/disable items
- `addPaymentToken()`: Add new payment tokens
- `removePaymentToken()`: Remove payment tokens
- `adminWithdraw()`: Withdraw contract funds

### Contract Admin

- `pause()` / `unpause()`: Pause/unpause contracts
- `setMarketplace()`: Link marketplace contract (HiLo)
- `setHiloContract()`: Link HiLo contract (Battle, Clan)
- `setClanContract()`: Link Clan contract (Battle)
- `setMarketplaceContract()`: Link Marketplace contract (Battle)

## 📊 Gas Estimates

| Function            | Average Gas | Notes                             |
| ------------------- | ----------- | --------------------------------- |
| `startGame()`       | ~65,000     | Initial game setup                |
| `makeGuess()`       | ~125,000    | Single prediction                 |
| `batchGuess()`      | ~200,000    | 10 predictions (requires TxBoost) |
| `resetGame()`       | ~50,000     | Start fresh                       |
| `purchaseItem()`    | ~150,000    | Buy marketplace item              |
| `createBattle()`    | ~175,000    | Challenge player                  |
| `acceptBattle()`    | ~100,000    | Accept invitation                 |
| `playBattleRound()` | ~130,000    | Battle prediction                 |
| `createClan()`      | ~250,000    | Create new clan (paid)            |
| `updateProfile()`   | ~80,000     | Update profile info               |

## 🛠️ Development Scripts

### Marketplace Management

```bash
# Add marketplace items
npm run add:usdt:items --network sepolia

# Update USDT prices
npm run update:usdt:prices --network sepolia

# Check marketplace items
npm run check:usdt:items --network sepolia
```

### Metadata Management

```bash
# Generate card metadata
npm run generate:metadata

# Update all metadata
npm run update:metadata

# Upload metadata to S3
npm run upload:metadata

# Set base URI
npm run set:baseuri --network sepolia
```

### Utility Scripts

```bash
# Clean build artifacts
npm run clean

# Type checking
npm run type-check
```

## 🔒 Security

### Security Features

- **ReentrancyGuard**: Prevents reentrancy attacks
- **CEI Pattern**: Checks-Effects-Interactions pattern enforced
- **Pausable**: Emergency pause mechanism
- **Access Control**: Role-based access control
- **Input Validation**: Comprehensive input checks
- **SafeERC20**: Secure token transfers
- **Custom Errors**: Gas-optimized error handling
- **Overflow Protection**: Built-in Solidity 0.8+ checks

## 📝 License

This project is licensed under the MIT License.

## 📞 Support

- **GitHub Issues**: Technical questions and bug reports
- **Documentation**: See `docs/` folder for detailed guides

---

**Note**: These contracts are deployed on testnets. Mainnet deployment will be announced separately.
