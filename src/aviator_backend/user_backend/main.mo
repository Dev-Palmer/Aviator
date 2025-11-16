// src/user_backend/main.mo
import Types "../shared/types";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Float "mo:base/Float";
import Time "mo:base/Time";
import Buffer "mo:base/Buffer";
import Order "mo:base/Order";

actor UserManagement {
    
    // Stable storage
    private stable var userStatsEntries : [(Principal, Types.UserStats)] = [];
    private stable var userBetHistoryEntries : [(Principal, [Nat])] = [];
    
    // Runtime state
    private var userStats = HashMap.HashMap<Principal, Types.UserStats>(10, Principal.equal, Principal.hash);
    private var userBetHistory = HashMap.HashMap<Principal, [Nat]>(10, Principal.equal, Principal.hash);
    
    // System functions
    system func preupgrade() {
        userStatsEntries := Iter.toArray(userStats.entries());
        userBetHistoryEntries := Iter.toArray(userBetHistory.entries());
    };
    
    system func postupgrade() {
        userStats := HashMap.fromIter<Principal, Types.UserStats>(userStatsEntries.vals(), 10, Principal.equal, Principal.hash);
        userBetHistory := HashMap.fromIter<Principal, [Nat]>(userBetHistoryEntries.vals(), 10, Principal.equal, Principal.hash);
        userStatsEntries := [];
        userBetHistoryEntries := [];
    };
    
    // Initialize or get user stats
    private func getOrCreateStats(user : Principal) : Types.UserStats {
        switch (userStats.get(user)) {
            case (?stats) { stats };
            case null {
                let newStats : Types.UserStats = {
                    totalBets = 0;
                    totalWagered = 0;
                    totalWon = 0;
                    totalLost = 0;
                    biggestWin = 0;
                    biggestMultiplier = 0.0;
                    averageMultiplier = 0.0;
                    winRate = 0.0;
                    lastPlayedAt = Nat64.fromNat(Int.abs(Time.now()));
                };
                userStats.put(user, newStats);
                newStats
            };
        };
    };
    
    // Update stats after a bet is placed
    public shared func recordBetPlaced(
        user : Principal,
        betId : Nat,
        amount : Types.TokenAmount
    ) : async () {
        let stats = getOrCreateStats(user);
        
        let updatedStats : Types.UserStats = {
            totalBets = stats.totalBets + 1;
            totalWagered = stats.totalWagered + amount;
            totalWon = stats.totalWon;
            totalLost = stats.totalLost;
            biggestWin = stats.biggestWin;
            biggestMultiplier = stats.biggestMultiplier;
            averageMultiplier = stats.averageMultiplier;
            winRate = stats.winRate;
            lastPlayedAt = Nat64.fromNat(Int.abs(Time.now()));
        };
        
        userStats.put(user, updatedStats);
        
        // Add to bet history
        let history = switch (userBetHistory.get(user)) {
            case (?h) { h };
            case null { [] };
        };
        let updatedHistory = Array.append<Nat>(history, [betId]);
        userBetHistory.put(user, updatedHistory);
    };
    
    // Update stats after a bet wins
    public shared func recordBetWon(
        user : Principal,
        amount : Types.TokenAmount,
        payout : Types.TokenAmount,
        multiplier : Float
    ) : async () {
        let stats = getOrCreateStats(user);
        let profit = if (payout > amount) { payout - amount } else { 0 };
        
        // Calculate new average multiplier
        let totalMultiplier = stats.averageMultiplier * Float.fromInt(stats.totalBets - 1);
        let newAverageMultiplier = if (stats.totalBets > 0) {
            (totalMultiplier + multiplier) / Float.fromInt(stats.totalBets)
        } else {
            multiplier
        };
        
        // Calculate wins for win rate
        let previousWins = Float.toInt(stats.winRate * Float.fromInt(stats.totalBets - 1));
        let totalWins = previousWins + 1;
        let newWinRate = Float.fromInt(totalWins) / Float.fromInt(stats.totalBets);
        
        let updatedStats : Types.UserStats = {
            totalBets = stats.totalBets;
            totalWagered = stats.totalWagered;
            totalWon = stats.totalWon + payout;
            totalLost = stats.totalLost;
            biggestWin = if (payout > stats.biggestWin) { payout } else { stats.biggestWin };
            biggestMultiplier = if (multiplier > stats.biggestMultiplier) { multiplier } else { stats.biggestMultiplier };
            averageMultiplier = newAverageMultiplier;
            winRate = newWinRate;
            lastPlayedAt = stats.lastPlayedAt;
        };
        
        userStats.put(user, updatedStats);
    };
    
    // Update stats after a bet loses
    public shared func recordBetLost(
        user : Principal,
        amount : Types.TokenAmount
    ) : async () {
        let stats = getOrCreateStats(user);
        
        // Calculate new average multiplier (0 for lost bet)
        let totalMultiplier = stats.averageMultiplier * Float.fromInt(stats.totalBets - 1);
        let newAverageMultiplier = if (stats.totalBets > 0) {
            totalMultiplier / Float.fromInt(stats.totalBets)
        } else {
            0.0
        };
        
        // Calculate wins for win rate (no new wins)
        let previousWins = Float.toInt(stats.winRate * Float.fromInt(stats.totalBets - 1));
        let newWinRate = Float.fromInt(previousWins) / Float.fromInt(stats.totalBets);
        
        let updatedStats : Types.UserStats = {
            totalBets = stats.totalBets;
            totalWagered = stats.totalWagered;
            totalWon = stats.totalWon;
            totalLost = stats.totalLost + amount;
            biggestWin = stats.biggestWin;
            biggestMultiplier = stats.biggestMultiplier;
            averageMultiplier = newAverageMultiplier;
            winRate = newWinRate;
            lastPlayedAt = stats.lastPlayedAt;
        };
        
        userStats.put(user, updatedStats);
    };
    
    // Query functions
    public query func getUserStats(user : Principal) : async ?Types.UserStats {
        userStats.get(user)
    };
    
    public query func getUserBetHistory(user : Principal, limit : Nat) : async [Nat] {
        switch (userBetHistory.get(user)) {
            case (?history) {
                let size = history.size();
                if (size <= limit) {
                    history
                } else {
                    // Return most recent bets
                    Array.tabulate<Nat>(limit, func(i) {
                        history[size - limit + i]
                    })
                }
            };
            case null { [] };
        }
    };
    
    // Get leaderboard by total won
    public query func getLeaderboardByWinnings(limit : Nat) : async [Types.LeaderboardEntry] {
        let entries = Buffer.Buffer<Types.LeaderboardEntry>(0);
        
        for ((user, stats) in userStats.entries()) {
            entries.add({
                player = user;
                totalWon = stats.totalWon;
                biggestWin = stats.biggestWin;
                biggestMultiplier = stats.biggestMultiplier;
                totalBets = stats.totalBets;
            });
        };
        
        // Sort by total won (descending)
        let sortedEntries = Array.sort<Types.LeaderboardEntry>(
            Buffer.toArray(entries),
            func(a, b) {
                if (a.totalWon > b.totalWon) { #less }
                else if (a.totalWon < b.totalWon) { #greater }
                else { #equal }
            }
        );
        
        // Return top N
        if (sortedEntries.size() <= limit) {
            sortedEntries
        } else {
            Array.tabulate<Types.LeaderboardEntry>(limit, func(i) {
                sortedEntries[i]
            })
        }
    };
    
    // Get leaderboard by biggest multiplier
    public query func getLeaderboardByMultiplier(limit : Nat) : async [Types.LeaderboardEntry] {
        let entries = Buffer.Buffer<Types.LeaderboardEntry>(0);
        
        for ((user, stats) in userStats.entries()) {
            if (stats.biggestMultiplier > 0.0) {
                entries.add({
                    player = user;
                    totalWon = stats.totalWon;
                    biggestWin = stats.biggestWin;
                    biggestMultiplier = stats.biggestMultiplier;
                    totalBets = stats.totalBets;
                });
            };
        };
        
        // Sort by biggest multiplier (descending)
        let sortedEntries = Array.sort<Types.LeaderboardEntry>(
            Buffer.toArray(entries),
            func(a, b) {
                if (a.biggestMultiplier > b.biggestMultiplier) { #less }
                else if (a.biggestMultiplier < b.biggestMultiplier) { #greater }
                else { #equal }
            }
        );
        
        // Return top N
        if (sortedEntries.size() <= limit) {
            sortedEntries
        } else {
            Array.tabulate<Types.LeaderboardEntry>(limit, func(i) {
                sortedEntries[i]
            })
        }
    };
    
    // Get total platform statistics
    public query func getPlatformStats() : async {
        totalUsers : Nat;
        totalBets : Nat;
        totalVolume : Types.TokenAmount;
        totalWinnings : Types.TokenAmount;
    } {
        var totalUsers = 0;
        var totalBets = 0;
        var totalVolume : Types.TokenAmount = 0;
        var totalWinnings : Types.TokenAmount = 0;
        
        for ((user, stats) in userStats.entries()) {
            totalUsers += 1;
            totalBets += stats.totalBets;
            totalVolume += stats.totalWagered;
            totalWinnings += stats.totalWon;
        };
        
        {
            totalUsers = totalUsers;
            totalBets = totalBets;
            totalVolume = totalVolume;
            totalWinnings = totalWinnings;
        }
    };
    
    // Get user rank by winnings
    public query func getUserRank(user : Principal) : async ?Nat {
        let allEntries = Buffer.Buffer<(Principal, Types.TokenAmount)>(0);
        
        for ((u, stats) in userStats.entries()) {
            allEntries.add((u, stats.totalWon));
        };
        
        // Sort by total won (descending)
        let sortedEntries = Array.sort<(Principal, Types.TokenAmount)>(
            Buffer.toArray(allEntries),
            func(a, b) {
                if (a.1 > b.1) { #less }
                else if (a.1 < b.1) { #greater }
                else { #equal }
            }
        );
        
        // Find user's rank
        var rank : ?Nat = null;
        var i = 0;
        for ((u, _) in sortedEntries.vals()) {
            if (Principal.equal(u, user)) {
                rank := ?(i + 1);
            };
            i += 1;
        };
        
        rank
    };
}