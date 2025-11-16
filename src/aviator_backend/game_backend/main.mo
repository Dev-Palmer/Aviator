// src/game_backend/main.mo
import Types "../shared/types";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Float "mo:base/Float";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Buffer "mo:base/Buffer";
import Result "mo:base/Result";
import Debug "mo:base/Debug";

actor class GameBackend(
    rngCanisterId : Principal,
    bettingCanisterId : Principal,
    userCanisterId : Principal
) = this {
    
    // Stable storage
    private stable var roundCounter : Nat = 0;
    private stable var roundsEntries : [(Nat, Types.Round)] = [];
    private stable var currentRoundId : ?Nat = null;
    
    // Runtime state
    private var rounds = HashMap.HashMap<Nat, Types.Round>(10, Nat.equal, Nat.hash);
    private var gameTimer : ?Timer.TimerId = null;
    
    // Game configuration
    private let BETTING_PHASE_DURATION : Nat64 = 5_000_000_000; // 5 seconds
    private let STARTING_PHASE_DURATION : Nat64 = 3_000_000_000; // 3 seconds
    
    // Canister references
    private let rngCanister : actor {
        generateCrashPoint : (Nat) -> async Float;
        calculateMultiplier : (Types.Timestamp, Types.Timestamp) -> async Float;
    } = actor(Principal.toText(rngCanisterId));
    
    private let bettingCanister : actor {
        placeBet : (Nat, Types.TokenAmount, ?Float) -> async Types.Result<Nat, Types.GameError>;
        cashout : (Nat, Float) -> async Types.Result<Types.TokenAmount, Types.GameError>;
        processCrashedBets : (Nat, Float) -> async Nat;
        getRoundBets : (Nat) -> async [Types.Bet];
    } = actor(Principal.toText(bettingCanisterId));
    
    private let userCanister : actor {
        recordBetPlaced : (Principal, Nat, Types.TokenAmount) -> async ();
        recordBetWon : (Principal, Types.TokenAmount, Types.TokenAmount, Float) -> async ();
        recordBetLost : (Principal, Types.TokenAmount) -> async ();
    } = actor(Principal.toText(userCanisterId));
    
    // System functions
    system func preupgrade() {
        roundsEntries := Iter.toArray(rounds.entries());
    };
    
    system func postupgrade() {
        rounds := HashMap.fromIter<Nat, Types.Round>(roundsEntries.vals(), 10, Nat.equal, Nat.hash);
        roundsEntries := [];
        
        // Restart game loop if there's an active round
        ignore startGameLoop();
    };
    
    // Start a new round
    private func startNewRound() : async () {
        roundCounter += 1;
        
        // Generate crash point
        let crashPoint = await rngCanister.generateCrashPoint(roundCounter);
        
        let newRound : Types.Round = {
            id = roundCounter;
            state = #Waiting;
            startTime = Nat64.fromNat(Int.abs(Time.now()));
            crashPoint = ?crashPoint;
            currentMultiplier = 1.0;
            seed = ""; // Placeholder
            totalBets = 0;
            totalPlayers = 0;
        };
        
        rounds.put(roundCounter, newRound);
        currentRoundId := ?roundCounter;
        
        // Start betting phase
        ignore Timer.setTimer<system>(
            #nanoseconds(Nat64.toNat(BETTING_PHASE_DURATION)),
            func() : async () {
                await startRound(roundCounter);
            }
        );
    };
    
    // Start the round (after betting phase)
    private func startRound(roundId : Nat) : async () {
        switch (rounds.get(roundId)) {
            case (?round) {
                let updatedRound : Types.Round = {
                    id = round.id;
                    state = #Starting;
                    startTime = round.startTime;
                    crashPoint = round.crashPoint;
                    currentMultiplier = round.currentMultiplier;
                    seed = round.seed;
                    totalBets = round.totalBets;
                    totalPlayers = round.totalPlayers;
                };
                rounds.put(roundId, updatedRound);
                
                // Wait for starting phase
                ignore Timer.setTimer<system>(
                    #nanoseconds(Nat64.toNat(STARTING_PHASE_DURATION)),
                    func() : async () {
                        await runRound(roundId);
                    }
                );
            };
            case null {};
        };
    };
    
    // Run the round (multiplier increases until crash)
    private func runRound(roundId : Nat) : async () {
        switch (rounds.get(roundId)) {
            case (?round) {
                let gameStartTime = Nat64.fromNat(Int.abs(Time.now()));
                
                let updatedRound : Types.Round = {
                    id = round.id;
                    state = #InProgress;
                    startTime = gameStartTime;
                    crashPoint = round.crashPoint;
                    currentMultiplier = 1.0;
                    seed = round.seed;
                    totalBets = round.totalBets;
                    totalPlayers = round.totalPlayers;
                };
                rounds.put(roundId, updatedRound);
                
                // Monitor multiplier until crash
                await monitorMultiplier(roundId, gameStartTime);
            };
            case null {};
        };
    };
    
    // Monitor multiplier and handle crash
    private func monitorMultiplier(roundId : Nat, startTime : Types.Timestamp) : async () {
        switch (rounds.get(roundId)) {
            case (?round) {
                switch (round.crashPoint) {
                    case (?crashPoint) {
                        let currentTime = Nat64.fromNat(Int.abs(Time.now()));
                        let multiplier = await rngCanister.calculateMultiplier(startTime, currentTime);
                        
                        if (multiplier >= crashPoint) {
                            // Game crashed!
                            await crashRound(roundId, crashPoint);
                        } else {
                            // Update multiplier and check auto-cashouts
                            let updatedRound : Types.Round = {
                                id = round.id;
                                state = round.state;
                                startTime = round.startTime;
                                crashPoint = round.crashPoint;
                                currentMultiplier = multiplier;
                                seed = round.seed;
                                totalBets = round.totalBets;
                                totalPlayers = round.totalPlayers;
                            };
                            rounds.put(roundId, updatedRound);
                            
                            // Process auto-cashouts
                            await processAutoCashouts(roundId, multiplier);
                            
                            // Continue monitoring (every 100ms)
                            ignore Timer.setTimer<system>(
                                #nanoseconds(100_000_000),
                                func() : async () {
                                    await monitorMultiplier(roundId, startTime);
                                }
                            );
                        };
                    };
                    case null {};
                };
            };
            case null {};
        };
    };
    
    // Process auto-cashouts for current multiplier
    private func processAutoCashouts(roundId : Nat, currentMultiplier : Float) : async () {
        let bets = await bettingCanister.getRoundBets(roundId);
        
        for (bet in bets.vals()) {
            switch (bet.autoCashout) {
                case (?targetMultiplier) {
                    if (currentMultiplier >= targetMultiplier and bet.status == #Active) {
                        // Auto cashout
                        let result = await bettingCanister.cashout(bet.id, targetMultiplier);
                        
                        switch (result) {
                            case (#ok(payout)) {
                                // Record win
                                await userCanister.recordBetWon(
                                    bet.player,
                                    bet.amount,
                                    payout,
                                    targetMultiplier
                                );
                            };
                            case (#err(_)) {};
                        };
                    };
                };
                case null {};
            };
        };
    };
    
    // Crash the round
    private func crashRound(roundId : Nat, crashPoint : Float) : async () {
        switch (rounds.get(roundId)) {
            case (?round) {
                let updatedRound : Types.Round = {
                    id = round.id;
                    state = #Crashed;
                    startTime = round.startTime;
                    crashPoint = ?crashPoint;
                    currentMultiplier = crashPoint;
                    seed = round.seed;
                    totalBets = round.totalBets;
                    totalPlayers = round.totalPlayers;
                };
                rounds.put(roundId, updatedRound);
                
                // Process all remaining active bets as losses
                let processedCount = await bettingCanister.processCrashedBets(roundId, crashPoint);
                
                // Record losses for users
                let bets = await bettingCanister.getRoundBets(roundId);
                for (bet in bets.vals()) {
                    if (bet.status == #Crashed) {
                        await userCanister.recordBetLost(bet.player, bet.amount);
                    };
                };
                
                // Mark round as completed
                let completedRound : Types.Round = {
                    id = round.id;
                    state = #Completed;
                    startTime = round.startTime;
                    crashPoint = ?crashPoint;
                    currentMultiplier = crashPoint;
                    seed = round.seed;
                    totalBets = round.totalBets;
                    totalPlayers = round.totalPlayers;
                };
                rounds.put(roundId, completedRound);
                
                // Wait before starting next round
                ignore Timer.setTimer<system>(
                    #nanoseconds(2_000_000_000), // 2 second pause
                    func() : async () {
                        await startNewRound();
                    }
                );
            };
            case null {};
        };
    };
    
    // Public functions
    
    // Place a bet (wrapper around betting canister)
    public shared(msg) func placeBet(
        amount : Types.TokenAmount,
        autoCashout : ?Float
    ) : async Types.Result<Nat, Types.GameError> {
        switch (currentRoundId) {
            case (?roundId) {
                switch (rounds.get(roundId)) {
                    case (?round) {
                        // Only allow bets during Waiting state
                        if (round.state != #Waiting) {
                            return #err(#RoundAlreadyStarted);
                        };
                        
                        let result = await bettingCanister.placeBet(roundId, amount, autoCashout);
                        
                        switch (result) {
                            case (#ok(betId)) {
                                // Update round stats
                                let updatedRound : Types.Round = {
                                    id = round.id;
                                    state = round.state;
                                    startTime = round.startTime;
                                    crashPoint = round.crashPoint;
                                    currentMultiplier = round.currentMultiplier;
                                    seed = round.seed;
                                    totalBets = round.totalBets + amount;
                                    totalPlayers = round.totalPlayers + 1;
                                };
                                rounds.put(roundId, updatedRound);
                                
                                // Record bet in user stats
                                await userCanister.recordBetPlaced(msg.caller, betId, amount);
                                
                                #ok(betId)
                            };
                            case (#err(e)) { #err(e) };
                        };
                    };
                    case null { #err(#GameNotStarted) };
                };
            };
            case null { #err(#GameNotStarted) };
        }
    };
    
    // Manual cashout
    public shared(msg) func cashout(betId : Nat) : async Types.Result<Types.TokenAmount, Types.GameError> {
        switch (currentRoundId) {
            case (?roundId) {
                switch (rounds.get(roundId)) {
                    case (?round) {
                        if (round.state != #InProgress) {
                            return #err(#CannotCashout);
                        };
                        
                        let result = await bettingCanister.cashout(betId, round.currentMultiplier);
                        
                        switch (result) {
                            case (#ok(payout)) {
                                // Get bet details to record stats
                                let bets = await bettingCanister.getRoundBets(roundId);
                                for (bet in bets.vals()) {
                                    if (bet.id == betId) {
                                        await userCanister.recordBetWon(
                                            msg.caller,
                                            bet.amount,
                                            payout,
                                            round.currentMultiplier
                                        );
                                    };
                                };
                                
                                #ok(payout)
                            };
                            case (#err(e)) { #err(e) };
                        };
                    };
                    case null { #err(#RoundNotActive) };
                };
            };
            case null { #err(#GameNotStarted) };
        }
    };
    
    // Start the game loop
    public shared(msg) func startGameLoop() : async () {
        if (currentRoundId == null) {
            await startNewRound();
        };
    };
    
    // Query functions
    
    public query func getCurrentRound() : async ?Types.Round {
        switch (currentRoundId) {
            case (?id) { rounds.get(id) };
            case null { null };
        }
    };
    
    public query func getRound(roundId : Nat) : async ?Types.Round {
        rounds.get(roundId)
    };
    
    public query func getRecentRounds(limit : Nat) : async [Types.Round] {
        let results = Buffer.Buffer<Types.Round>(limit);
        var count = 0;
        var id = roundCounter;
        
        while (count < limit and id > 0) {
            switch (rounds.get(id)) {
                case (?round) {
                    results.add(round);
                    count += 1;
                };
                case null {};
            };
            id -= 1;
        };
        
        Buffer.toArray(results)
    };
    
    public query func getTotalRounds() : async Nat {
        roundCounter
    };
}