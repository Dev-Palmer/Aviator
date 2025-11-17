# Aviator Game - ckBTC Edition | Encode Hackathon

A fully decentralized Aviator-style crash game built on the Internet Computer Protocol (ICP) using Motoko and integrated with ckBTC for seamless Bitcoin-based betting.

## 🎮 Game Overview

Aviator is a popular multiplayer betting game where:
- A multiplier starts at 1.0x and increases exponentially
- Players can bet ckBTC before the round starts
- Players can cash out at any time to lock in their winnings at the current multiplier
- The game randomly "crashes" at a predetermined point
- Players who haven't cashed out before the crash lose their bet
- Auto-cashout feature allows setting a target multiplier

## 🏗️ Architecture

This project implements a **multi-canister architecture** for optimal scalability and separation of concerns:

### 1. **RNG Backend Canister**
- Generates provably fair crash points using IC's random beacon
- Calculates real-time multipliers based on exponential growth
- Stores seed history for verification
- Uses exponential distribution for realistic crash probabilities

### 2. **Betting Backend Canister**
- Full ICRC-1/ICRC-2 ckBTC integration
- Manages user deposits and withdrawals
- Processes bets and payouts atomically
- Handles escrow for active bets
- Integrates with the official ckBTC ledger canister

### 3. **User Backend Canister**
- Tracks comprehensive user statistics
- Maintains betting history
- Generates leaderboards (by winnings and multipliers)
- Calculates win rates and averages
- Provides ranking system

### 4. **Game Backend Canister**
- Orchestrates game rounds and state management
- Coordinates between all other canisters
- Implements game loop with timer-based progression
- Handles auto-cashout logic
- Manages round phases (Waiting → Starting → InProgress → Crashed)

## 🚀 Quick Start

### Prerequisites

```bash
# Install dfx (Internet Computer SDK)
sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"

# Verify installation
dfx --version
```

### Local Development

1. **Clone and Setup**
```bash
git clone <your-repo>
cd aviator-game
chmod +x deploy.sh
```

2. **Deploy All Canisters**
```bash
./deploy.sh local
```

This script will:
- Start a local IC replica
- Deploy a local ckBTC ledger with test tokens
- Deploy all game canisters in the correct order
- Wire up all inter-canister dependencies
- Start the game loop automatically

3. **Approve Spending** (Required for ICRC-2)
```bash
# Get your betting canister ID from .env
source .env

# Approve the betting canister to spend your tokens
dfx canister call icrc1_ledger icrc2_approve "(record { 
  amount = 100_000_000; 
  spender = record { 
    owner = principal \"$BETTING_CANISTER_ID\" 
  } 
})"
```

4. **Deposit ckBTC**
```bash
# Deposit 1,000,000 satoshis (0.01 ckBTC)
dfx canister call betting_backend deposit "(1_000_000)"
```

5. **Place Your First Bet**
```bash
# Bet 100,000 satoshis with auto-cashout at 2.0x
dfx canister call game_backend placeBet "(100_000, opt 2.0)"

# Or bet without auto-cashout
dfx canister call game_backend placeBet "(100_000, null)"
```

6. **Monitor the Game**
```bash
# View current round
dfx canister call game_backend getCurrentRound

# Check your balance
dfx canister call betting_backend getUserBalance "(principal \"$(dfx identity get-principal)\")"

# View your stats
dfx canister call user_backend getUserStats "(principal \"$(dfx identity get-principal)\")"
```

## 📊 Game Flow

```
┌─────────────────┐
│  Betting Phase  │  (5 seconds)
│   Players can   │  - Place bets
│   place bets    │  - Set auto-cashout
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Starting Phase  │  (3 seconds)
│  Countdown to   │  - No new bets
│  game start     │  - RNG generates crash point
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Game In Progress│  (Variable)
│  Multiplier     │  - Multiplier increases
│  increases      │  - Players can cash out
│                 │  - Auto-cashouts trigger
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Game Crash    │  (2 seconds)
│  Crash point    │  - Active bets lose
│  reached        │  - Winnings distributed
└────────┬────────┘
         │
         └──────► Next Round
```

## 💰 ckBTC Integration

### Local Testing
The deployment script creates a local ckBTC ledger with ICRC-1 and ICRC-2 support, giving you 100,000,000,000 satoshis (1,000 ckBTC) for testing.

### Mainnet Deployment
For mainnet, the canisters connect to the official ckBTC infrastructure:

- **ckBTC Ledger**: `mxzaz-hqaaa-aaaar-qaada-cai`
- **ckBTC Index**: `n5wcd-faaaa-aaaar-qaaea-cai`
- **ckBTC Minter**: `mqygn-kiaaa-aaaar-qaadq-cai`

```bash
# Deploy to mainnet
./deploy.sh ic

# You'll need real ckBTC - get it from the minter
# Visit: https://mqygn-kiaaa-aaaar-qaadq-cai.raw.icp0.io/dashboard
```

### ICRC-2 Approve/Transfer Pattern
The betting canister uses the secure ICRC-2 pattern:
1. User approves the betting canister
2. Betting canister uses `transfer_from` to move tokens
3. This prevents direct transfers and enhances security

## 🎯 Key Features

### Provably Fair
- Uses IC's random beacon for entropy
- Crash points generated before round starts
- Seeds stored and verifiable on-chain
- Exponential distribution for realistic gameplay

### Security
- Atomic bet and payout operations
- Rollback handling for failed transfers
- Input validation on all public methods
- Access control for administrative functions
- No reentrancy vulnerabilities

### User Experience
- Real-time multiplier updates every 100ms
- Auto-cashout at target multipliers
- Comprehensive statistics tracking
- Leaderboards and rankings
- Historical bet tracking

## 📝 API Reference

### Game Backend

```motoko
// Place a bet
placeBet(amount: TokenAmount, autoCashout: ?Float) : async Result<Nat, GameError>

// Manual cashout
cashout(betId: Nat) : async Result<TokenAmount, GameError>

// Query current round
getCurrentRound() : async ?Round

// Get recent rounds
getRecentRounds(limit: Nat) : async [Round]
```

### Betting Backend

```motoko
// Deposit ckBTC
deposit(amount: TokenAmount) : async Result<TokenAmount, GameError>

// Withdraw ckBTC
withdraw(amount: TokenAmount) : async Result<TokenAmount, GameError>

// Check balance
getUserBalance(user: Principal) : async TokenAmount

// Get user's bets
getUserBets(user: Principal, limit: Nat) : async [Bet]
```

### User Backend

```motoko
// Get user statistics
getUserStats(user: Principal) : async ?UserStats

// Get leaderboard by winnings
getLeaderboardByWinnings(limit: Nat) : async [LeaderboardEntry]

// Get leaderboard by multiplier
getLeaderboardByMultiplier(limit: Nat) : async [LeaderboardEntry]

// Get platform statistics
getPlatformStats() : async PlatformStats
```

### RNG Backend

```motoko
// Generate crash point (admin only)
generateCrashPoint(roundId: Nat) : async Float

// Verify previous seed
verifySeed(roundId: Nat) : async ?Blob

// Calculate current multiplier
calculateMultiplier(startTime: Timestamp, currentTime: Timestamp) : async Float
```

## 🧪 Testing

### Unit Testing
```bash
# Test individual canister functions
dfx canister call rng_backend generateCrashPoint "(1)"
dfx canister call betting_backend getUserBalance "(principal \"aaaaa-aa\")"
```

### Integration Testing
```bash
# Full game flow test
# 1. Deposit
dfx canister call betting_backend deposit "(10_000_000)"

# 2. Place bet
BET_ID=$(dfx canister call game_backend placeBet "(1_000_000, opt 2.0)" | grep -o '[0-9]*')

# 3. Wait for round to progress
sleep 10

# 4. Check result
dfx canister call betting_backend getBet "($BET_ID)"

# 5. Check stats
dfx canister call user_backend getUserStats "(principal \"$(dfx identity get-principal)\")"
```

## 📈 Configuration

### Game Parameters (Adjustable in code)

```motoko
// In game_backend/main.mo
BETTING_PHASE_DURATION = 5_000_000_000  // 5 seconds
STARTING_PHASE_DURATION = 3_000_000_000 // 3 seconds

// In betting_backend/main.mo
MIN_BET = 10_000        // 0.0001 ckBTC
MAX_BET = 100_000_000   // 1 ckBTC
TRANSFER_FEE = 10       // Standard ckBTC fee

// In rng_backend/main.mo
HOUSE_EDGE = 0.01       // 1% house edge
```

### Multiplier Distribution
- 50% chance: 1.0x - 2.0x
- 30% chance: 2.0x - 3.0x
- 15% chance: 3.0x - 10.0x
- 4% chance: 10.0x - 100.0x
- 1% chance: 100.0x+

## 🔒 Security Considerations

1. **ICRC-2 Approval Pattern**: Users must approve before depositing
2. **Atomic Operations**: All financial transactions are atomic
3. **Error Handling**: Comprehensive error handling with rollback
4. **Rate Limiting**: Can be added for high-frequency operations
5. **Input Validation**: All user inputs are validated
6. **Access Control**: Admin functions are protected

## 🚨 Known Limitations

1. **Timer Precision**: IC timers have ~1 second precision, affecting multiplier updates
2. **Gas Costs**: Multiple inter-canister calls can be expensive on mainnet
3. **Scalability**: Consider sharding for high user volumes
4. **State Management**: Large state requires careful upgrade handling

## 🛠️ Advanced Topics

### Upgrading Canisters
```bash
# Upgrade with state preservation
dfx deploy --network ic game_backend --mode upgrade
```

### Monitoring
```bash
# Check canister cycles
dfx canister status game_backend --network ic

# View logs (local only)
dfx canister logs game_backend
```

### Backup
```bash
# Export stable state
dfx canister call user_backend getUserStats "(principal \"...\")" > backup.txt
```

## 📚 Resources

- [ICP Documentation](https://internetcomputer.org/docs)
- [ckBTC Overview](https://internetcomputer.org/docs/defi/chain-key-tokens/ckbtc/overview)
- [ICRC-1 Standard](https://github.com/dfinity/ICRC-1/blob/main/standards/ICRC-1/README.md)
- [ICRC-2 Standard](https://github.com/dfinity/ICRC-1/blob/main/standards/ICRC-2/README.md)
- [Motoko Programming Guide](https://internetcomputer.org/docs/motoko/main/about-this-guide)

## 🤝 Contributing

Contributions are welcome! Areas for improvement:
- Frontend UI development
- Additional game modes
- Enhanced statistics
- Mobile app integration
- Social features

## 📄 License

MIT License - feel free to use and modify for your projects

## ⚠️ Disclaimer

This is educational software. Gambling may be illegal in your jurisdiction. Users are responsible for compliance with local laws. No warranty provided.

---

Built with ❤️ on the Internet Computer