// src/betting_backend/main.mo
import Types "../shared/types";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Result "mo:base/Result";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";

actor class BettingBackend(ledgerCanisterId : Principal) = this {
    
    // Stable storage
    private stable var betCounter : Nat = 0;
    private stable var betsEntries : [(Nat, Types.Bet)] = [];
    private stable var userBalancesEntries : [(Principal, Types.TokenAmount)] = [];
    private stable var totalVolumeProcessed : Types.TokenAmount = 0;
    
    // Runtime state
    private var bets = HashMap.HashMap<Nat, Types.Bet>(10, Nat.equal, Nat.hash);
    private var userBalances = HashMap.HashMap<Principal, Types.TokenAmount>(10, Principal.equal, Principal.hash);
    private var activeBets = HashMap.HashMap<Nat, [Nat]>(10, Nat.equal, Nat.hash); // roundId -> [betIds]
    
    // Constants
    private let MIN_BET : Types.TokenAmount = 10_000; // 0.0001 ckBTC (10k satoshi)
    private let MAX_BET : Types.TokenAmount = 100_000_000; // 1 ckBTC
    private let TRANSFER_FEE : Types.TokenAmount = 10; // ckBTC standard fee
    
    // ICRC-1 Ledger interface
    private let ledger : actor {
        icrc1_transfer : (Types.TransferArgs) -> async Types.TransferResult;
        icrc1_balance_of : (Types.Account) -> async Types.TokenAmount;
        icrc2_approve : (Types.ApproveArgs) -> async Types.ApproveResult;
        icrc2_transfer_from : (Types.TransferFromArgs) -> async Types.TransferFromResult;
    } = actor(Principal.toText(ledgerCanisterId));
    
    // System functions
    system func preupgrade() {
        betsEntries := Iter.toArray(bets.entries());
        userBalancesEntries := Iter.toArray(userBalances.entries());
    };
    
    system func postupgrade() {
        bets := HashMap.fromIter<Nat, Types.Bet>(betsEntries.vals(), 10, Nat.equal, Nat.hash);
        userBalances := HashMap.fromIter<Principal, Types.TokenAmount>(userBalancesEntries.vals(), 10, Principal.equal, Principal.hash);
        betsEntries := [];
        userBalancesEntries := [];
    };
    
    // Deposit ckBTC to betting canister
    public shared(msg) func deposit(amount : Types.TokenAmount) : async Types.Result<Types.TokenAmount, Types.GameError> {
        let caller = msg.caller;
        
        if (amount < MIN_BET) {
            return #err(#BetTooLow);
        };
        
        // Transfer from user to this canister
        let transferArgs : Types.TransferFromArgs = {
            spender_subaccount = null;
            from = { owner = caller; subaccount = null };
            to = { owner = Principal.fromActor(this); subaccount = null };
            amount = amount;
            fee = ?TRANSFER_FEE;
            memo = null;
            created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
        };
        
        try {
            let result = await ledger.icrc2_transfer_from(transferArgs);
            
            switch (result) {
                case (#Ok(blockIndex)) {
                    // Update user balance
                    let currentBalance = switch (userBalances.get(caller)) {
                        case (?balance) { balance };
                        case null { 0 };
                    };
                    userBalances.put(caller, currentBalance + amount);
                    #ok(currentBalance + amount)
                };
                case (#Err(error)) {
                    #err(#TransferFailed("Transfer failed"))
                };
            };
        } catch (e) {
            #err(#TransferFailed("Transfer call failed"))
        };
    };
    
    // Withdraw ckBTC from betting canister
    public shared(msg) func withdraw(amount : Types.TokenAmount) : async Types.Result<Types.TokenAmount, Types.GameError> {
        let caller = msg.caller;
        
        let currentBalance = switch (userBalances.get(caller)) {
            case (?balance) { balance };
            case null { 0 };
        };
        
        if (currentBalance < amount + TRANSFER_FEE) {
            return #err(#InsufficientBalance);
        };
        
        // Transfer from canister to user
        let transferArgs : Types.TransferArgs = {
            from_subaccount = null;
            to = { owner = caller; subaccount = null };
            amount = amount;
            fee = ?TRANSFER_FEE;
            memo = null;
            created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
        };
        
        try {
            let result = await ledger.icrc1_transfer(transferArgs);
            
            switch (result) {
                case (#Ok(blockIndex)) {
                    userBalances.put(caller, currentBalance - amount - TRANSFER_FEE);
                    #ok(currentBalance - amount - TRANSFER_FEE)
                };
                case (#Err(error)) {
                    #err(#TransferFailed("Withdrawal failed"))
                };
            };
        } catch (e) {
            #err(#TransferFailed("Withdrawal call failed"))
        };
    };
    
    // Place a bet for the current/next round
    public shared(msg) func placeBet(
        roundId : Nat,
        amount : Types.TokenAmount,
        autoCashout : ?Float
    ) : async Types.Result<Nat, Types.GameError> {
        let caller = msg.caller;
        
        // Validate bet amount
        if (amount < MIN_BET) {
            return #err(#BetTooLow);
        };
        
        if (amount > MAX_BET) {
            return #err(#BetTooHigh);
        };
        
        // Check user balance
        let currentBalance = switch (userBalances.get(caller)) {
            case (?balance) { balance };
            case null { 0 };
        };
        
        if (currentBalance < amount) {
            return #err(#InsufficientBalance);
        };
        
        // Check if user already has an active bet in this round
        switch (activeBets.get(roundId)) {
            case (?betIds) {
                for (betId in betIds.vals()) {
                    switch (bets.get(betId)) {
                        case (?existingBet) {
                            if (existingBet.player == caller and existingBet.status == #Active) {
                                return #err(#AlreadyBet);
                            };
                        };
                        case null {};
                    };
                };
            };
            case null {};
        };
        
        // Create bet
        betCounter += 1;
        let bet : Types.Bet = {
            id = betCounter;
            roundId = roundId;
            player = caller;
            amount = amount;
            autoCashout = autoCashout;
            cashoutMultiplier = null;
            status = #Active;
            placedAt = Nat64.fromNat(Int.abs(Time.now()));
            settledAt = null;
            payout = 0;
        };
        
        // Deduct from user balance
        userBalances.put(caller, currentBalance - amount);
        
        // Store bet
        bets.put(betCounter, bet);
        
        // Add to active bets for round
        let roundBets = switch (activeBets.get(roundId)) {
            case (?existing) { existing };
            case null { [] };
        };
        let updatedBets = Array.append<Nat>(roundBets, [betCounter]);
        activeBets.put(roundId, updatedBets);
        
        // Update volume
        totalVolumeProcessed += amount;
        
        #ok(betCounter)
    };
    
    // Cashout a bet at current multiplier
    public shared(msg) func cashout(betId : Nat, multiplier : Float) : async Types.Result<Types.TokenAmount, Types.GameError> {
        let caller = msg.caller;
        
        switch (bets.get(betId)) {
            case (?bet) {
                // Verify ownership
                if (bet.player != caller) {
                    return #err(#NotAuthorized);
                };
                
                // Check if bet is active
                if (bet.status != #Active) {
                    return #err(#CannotCashout);
                };
                
                // Validate multiplier
                if (multiplier < 1.0) {
                    return #err(#InvalidMultiplier);
                };
                
                // Calculate payout
                let payout = Nat64.toNat(Nat64.fromNat(bet.amount) * Nat64.fromNat(Int.abs(Float.toInt(multiplier * 100.0)))) / 100;
                
                // Update bet
                let updatedBet : Types.Bet = {
                    id = bet.id;
                    roundId = bet.roundId;
                    player = bet.player;
                    amount = bet.amount;
                    autoCashout = bet.autoCashout;
                    cashoutMultiplier = ?multiplier;
                    status = #CashedOut;
                    placedAt = bet.placedAt;
                    settledAt = ?Nat64.fromNat(Int.abs(Time.now()));
                    payout = payout;
                };
                
                bets.put(betId, updatedBet);
                
                // Credit user balance
                let currentBalance = switch (userBalances.get(caller)) {
                    case (?balance) { balance };
                    case null { 0 };
                };
                userBalances.put(caller, currentBalance + payout);
                
                #ok(payout)
            };
            case null {
                #err(#InvalidBet)
            };
        };
    };
    
    // Process crashed bets (called by game canister)
    public shared(msg) func processCrashedBets(roundId : Nat, crashPoint : Float) : async Nat {
        var processedCount = 0;
        
        switch (activeBets.get(roundId)) {
            case (?betIds) {
                for (betId in betIds.vals()) {
                    switch (bets.get(betId)) {
                        case (?bet) {
                            if (bet.status == #Active) {
                                let updatedBet : Types.Bet = {
                                    id = bet.id;
                                    roundId = bet.roundId;
                                    player = bet.player;
                                    amount = bet.amount;
                                    autoCashout = bet.autoCashout;
                                    cashoutMultiplier = null;
                                    status = #Crashed;
                                    placedAt = bet.placedAt;
                                    settledAt = ?Nat64.fromNat(Int.abs(Time.now()));
                                    payout = 0;
                                };
                                bets.put(betId, updatedBet);
                                processedCount += 1;
                            };
                        };
                        case null {};
                    };
                };
                
                // Remove from active bets
                activeBets.delete(roundId);
            };
            case null {};
        };
        
        processedCount
    };
    
    // Query functions
    public query func getUserBalance(user : Principal) : async Types.TokenAmount {
        switch (userBalances.get(user)) {
            case (?balance) { balance };
            case null { 0 };
        }
    };
    
    public query func getBet(betId : Nat) : async ?Types.Bet {
        bets.get(betId)
    };
    
    public query func getUserBets(user : Principal, limit : Nat) : async [Types.Bet] {
        let results = Buffer.Buffer<Types.Bet>(limit);
        var count = 0;
        
        for ((id, bet) in bets.entries()) {
            if (bet.player == user and count < limit) {
                results.add(bet);
                count += 1;
            };
        };
        
        Buffer.toArray(results)
    };
    
    public query func getRoundBets(roundId : Nat) : async [Types.Bet] {
        switch (activeBets.get(roundId)) {
            case (?betIds) {
                let results = Buffer.Buffer<Types.Bet>(betIds.size());
                for (betId in betIds.vals()) {
                    switch (bets.get(betId)) {
                        case (?bet) { results.add(bet) };
                        case null {};
                    };
                };
                Buffer.toArray(results)
            };
            case null { [] };
        }
    };
    
    public query func getTotalVolume() : async Types.TokenAmount {
        totalVolumeProcessed
    };
    
    public query func getActiveBetsCount(roundId : Nat) : async Nat {
        switch (activeBets.get(roundId)) {
            case (?betIds) { betIds.size() };
            case null { 0 };
        }
    };
}