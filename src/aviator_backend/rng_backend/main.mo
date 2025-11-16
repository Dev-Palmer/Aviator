// src/rng_backend/main.mo
import Types "../shared/types";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Float "mo:base/Float";
import Int "mo:base/Int";
import Random "mo:base/Random";
import Time "mo:base/Time";
import Buffer "mo:base/Buffer";

actor RNG {
    
    // Stable storage
    private stable var roundCounter : Nat = 0;
    private stable var seedHistory : [(Nat, Blob)] = [];
    
    // House edge configuration (1% house edge)
    private let HOUSE_EDGE : Float = 0.01;
    
    // Generate crash point using provably fair algorithm
    public shared func generateCrashPoint(roundId : Nat) : async Float {
        // Get random seed from IC
        let entropy = await Random.blob();
        
        // Store seed for verification
        let historyBuffer = Buffer.Buffer<(Nat, Blob)>(seedHistory.size() + 1);
        for (entry in seedHistory.vals()) {
            historyBuffer.add(entry);
        };
        historyBuffer.add((roundId, entropy));
        seedHistory := Buffer.toArray(historyBuffer);
        
        // Keep only last 100 seeds
        if (seedHistory.size() > 100) {
            seedHistory := Array.tabulate<(Nat, Blob)>(
                100,
                func(i) { seedHistory[seedHistory.size() - 100 + i] }
            );
        };
        
        // Convert entropy to crash point
        let crashPoint = entropyToCrashPoint(entropy);
        crashPoint
    };
    
    // Convert entropy blob to crash point using exponential distribution
    private func entropyToCrashPoint(entropy : Blob) : Float {
        let bytes = Blob.toArray(entropy);
        
        // Take first 4 bytes and convert to Nat32
        var value : Nat32 = 0;
        var i = 0;
        while (i < 4 and i < bytes.size()) {
            value := value * 256 + Nat32.fromNat(Nat8.toNat(bytes[i]));
            i += 1;
        };
        
        // Convert to float between 0 and 1
        let randomFloat = Float.fromInt(Int.abs(Nat32.toNat(value))) / 4294967295.0;
        
        // Apply house edge
        let adjustedFloat = randomFloat * (1.0 - HOUSE_EDGE);
        
        // Use exponential distribution for crash point
        // Most common crashes are between 1.0x and 3.0x
        // With occasional high multipliers
        if (adjustedFloat >= 0.99) {
            // 1% chance of 100x+
            return 100.0 + (adjustedFloat - 0.99) * 10000.0;
        } else if (adjustedFloat >= 0.95) {
            // 4% chance of 10x-100x
            return 10.0 + (adjustedFloat - 0.95) * 2250.0;
        } else if (adjustedFloat >= 0.80) {
            // 15% chance of 3x-10x
            return 3.0 + (adjustedFloat - 0.80) * 46.67;
        } else if (adjustedFloat >= 0.50) {
            // 30% chance of 2x-3x
            return 2.0 + (adjustedFloat - 0.50) * 3.33;
        } else {
            // 50% chance of 1.0x-2.0x
            return 1.0 + adjustedFloat * 2.0;
        };
    };
    
    // Verify a previous round's seed
    public query func verifySeed(roundId : Nat) : async ?Blob {
        for ((id, seed) in seedHistory.vals()) {
            if (id == roundId) {
                return ?seed;
            };
        };
        null
    };
    
    // Get multiple crash points for batch generation
    public shared func generateBatchCrashPoints(count : Nat) : async [Float] {
        let results = Buffer.Buffer<Float>(count);
        var i = 0;
        
        while (i < count) {
            roundCounter += 1;
            let crashPoint = await generateCrashPoint(roundCounter);
            results.add(crashPoint);
            i += 1;
        };
        
        Buffer.toArray(results)
    };
    
    // Calculate current multiplier based on time elapsed
    public func calculateMultiplier(startTime : Types.Timestamp, currentTime : Types.Timestamp) : Float {
        let elapsedSeconds = Float.fromInt(Int.abs(Nat64.toNat(currentTime - startTime))) / 1_000_000_000.0;
        
        // Multiplier grows exponentially
        // Formula: 1.0 * e^(0.08 * t) where t is time in seconds
        let growthRate = 0.08;
        let multiplier = Float.exp(growthRate * elapsedSeconds);
        
        // Round to 2 decimal places
        Float.fromInt(Int.abs(Float.toInt(multiplier * 100.0))) / 100.0
    };
    
    // Get time to reach a specific multiplier
    public func getTimeForMultiplier(targetMultiplier : Float) : Nat64 {
        // Inverse of exponential growth: t = ln(multiplier) / 0.08
        let growthRate = 0.08;
        let timeSeconds = Float.log(targetMultiplier) / growthRate;
        let timeNanos = timeSeconds * 1_000_000_000.0;
        
        Nat64.fromNat(Int.abs(Float.toInt(timeNanos)))
    };
    
    // Get statistics about generated crash points
    public query func getGenerationStats() : async {
        totalGenerated : Nat;
        historySize : Nat;
    } {
        {
            totalGenerated = roundCounter;
            historySize = seedHistory.size();
        }
    };
    
    // Admin: Clear old history
    public shared(msg) func clearOldHistory() : async () {
        // Keep only last 50 seeds
        if (seedHistory.size() > 50) {
            seedHistory := Array.tabulate<(Nat, Blob)>(
                50,
                func(i) { seedHistory[seedHistory.size() - 50 + i] }
            );
        };
    };
}