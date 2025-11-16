// src/shared/types.mo
module {
    public type Timestamp = Nat64;
    public type TokenAmount = Nat;
    
    // User Account (ICRC-1 standard)
    public type Account = {
        owner : Principal;
        subaccount : ?Blob;
    };
    
    // Game Round States
    public type RoundState = {
        #Waiting;
        #Starting;
        #InProgress;
        #Crashed;
        #Completed;
    };
    
    // Game Round
    public type Round = {
        id : Nat;
        state : RoundState;
        startTime : Timestamp;
        crashPoint : ?Float;
        currentMultiplier : Float;
        seed : Blob;
        totalBets : TokenAmount;
        totalPlayers : Nat;
    };
    
    // Bet Status
    public type BetStatus = {
        #Active;
        #CashedOut;
        #Crashed;
        #Cancelled;
    };
    
    // Player Bet
    public type Bet = {
        id : Nat;
        roundId : Nat;
        player : Principal;
        amount : TokenAmount;
        autoCashout : ?Float;
        cashoutMultiplier : ?Float;
        status : BetStatus;
        placedAt : Timestamp;
        settledAt : ?Timestamp;
        payout : TokenAmount;
    };
    
    // User Statistics
    public type UserStats = {
        totalBets : Nat;
        totalWagered : TokenAmount;
        totalWon : TokenAmount;
        totalLost : TokenAmount;
        biggestWin : TokenAmount;
        biggestMultiplier : Float;
        averageMultiplier : Float;
        winRate : Float;
        lastPlayedAt : Timestamp;
    };
    
    // Leaderboard Entry
    public type LeaderboardEntry = {
        player : Principal;
        totalWon : TokenAmount;
        biggestWin : TokenAmount;
        biggestMultiplier : Float;
        totalBets : Nat;
    };
    
    // ICRC-1 Transfer Args
    public type TransferArgs = {
        from_subaccount : ?Blob;
        to : Account;
        amount : TokenAmount;
        fee : ?TokenAmount;
        memo : ?Blob;
        created_at_time : ?Timestamp;
    };
    
    // ICRC-1 Transfer Result
    public type TransferResult = {
        #Ok : Nat;
        #Err : TransferError;
    };
    
    public type TransferError = {
        #BadFee : { expected_fee : TokenAmount };
        #BadBurn : { min_burn_amount : TokenAmount };
        #InsufficientFunds : { balance : TokenAmount };
        #TooOld;
        #CreatedInFuture : { ledger_time : Timestamp };
        #Duplicate : { duplicate_of : Nat };
        #TemporarilyUnavailable;
        #GenericError : { error_code : Nat; message : Text };
    };
    
    // ICRC-2 Approve Args
    public type ApproveArgs = {
        from_subaccount : ?Blob;
        spender : Account;
        amount : TokenAmount;
        expected_allowance : ?TokenAmount;
        expires_at : ?Timestamp;
        fee : ?TokenAmount;
        memo : ?Blob;
        created_at_time : ?Timestamp;
    };
    
    // ICRC-2 Approve Result
    public type ApproveResult = {
        #Ok : Nat;
        #Err : ApproveError;
    };
    
    public type ApproveError = {
        #BadFee : { expected_fee : TokenAmount };
        #InsufficientFunds : { balance : TokenAmount };
        #AllowanceChanged : { current_allowance : TokenAmount };
        #Expired : { ledger_time : Timestamp };
        #TooOld;
        #CreatedInFuture : { ledger_time : Timestamp };
        #Duplicate : { duplicate_of : Nat };
        #TemporarilyUnavailable;
        #GenericError : { error_code : Nat; message : Text };
    };
    
    // ICRC-2 Transfer From Args
    public type TransferFromArgs = {
        spender_subaccount : ?Blob;
        from : Account;
        to : Account;
        amount : TokenAmount;
        fee : ?TokenAmount;
        memo : ?Blob;
        created_at_time : ?Timestamp;
    };
    
    // ICRC-2 Transfer From Result
    public type TransferFromResult = {
        #Ok : Nat;
        #Err : TransferFromError;
    };
    
    public type TransferFromError = {
        #BadFee : { expected_fee : TokenAmount };
        #BadBurn : { min_burn_amount : TokenAmount };
        #InsufficientFunds : { balance : TokenAmount };
        #InsufficientAllowance : { allowance : TokenAmount };
        #TooOld;
        #CreatedInFuture : { ledger_time : Timestamp };
        #Duplicate : { duplicate_of : Nat };
        #TemporarilyUnavailable;
        #GenericError : { error_code : Nat; message : Text };
    };
    
    // Error Types
    public type GameError = {
        #NotAuthorized;
        #RoundNotActive;
        #RoundAlreadyStarted;
        #InvalidBet;
        #InsufficientBalance;
        #BetTooLow;
        #BetTooHigh;
        #AlreadyBet;
        #CannotCashout;
        #TransferFailed : Text;
        #GameNotStarted;
        #InvalidMultiplier;
    };
    
    // Result Types
    public type Result<Ok, Err> = {
        #ok : Ok;
        #err : Err;
    };
}