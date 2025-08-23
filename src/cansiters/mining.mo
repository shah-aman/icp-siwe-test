import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Random "mo:base/Random";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Bool "mo:base/Bool";
import Timer "mo:base/Timer";
import HashMap "mo:base/HashMap";
import Cycles "mo:base/ExperimentalCycles";
import Order "mo:base/Order";


// Import production-grade token type definitions
import ICRCToken "../tokens/ICRC";

actor Mining {

  // Token & owner configuration - Updated for mainnet deployment
  private stable var dirtTokenCanister: Principal = Principal.fromText("5lkcq-gaaaa-aaaaj-qnrfq-cai"); // DRIFT token on mainnet
  private stable var ak69TokenCanister: Principal = Principal.fromText("zm55w-7aaaa-aaaae-qffrq-cai"); // AK69 token on mainnet
  private stable var owner: Principal = Principal.fromText("hpikg-6exdt-jn33w-ndty3-fc7jc-tl2lr-buih3-cs3y7-tftkp-sfp62-gqe"); // Default to current owner
  private stable var miningCanisterPrincipal: ?Principal = null; // Will be initialized on first run
  private let BURN_ADDRESS = Principal.fromText("aaaaa-aa"); // Standard burn address
  
  // Mining configuration
  private let BLOCK_REWARD: Nat = 150_000_000_000; // 150 AK69 (assuming 9 decimals)
  private let MIN_DAILY_DIRT_RATE: Nat = 1_000_000_000_000_000_000; // 1 billion DRIFT tokens/day minimum  
  private let MAX_DAILY_DIRT_RATE: Nat = 10_000_000_000_000_000_000; // 10 billion DRIFT tokens/day maximum
  
  // Block timing - 11.429 minutes = 685.74 seconds
  private let BLOCK_DURATION_SECONDS: Nat = 686; // Rounded to 686 seconds
  private let BLOCK_DURATION_NS: Int = 686 * 1_000_000_000; // Nanoseconds for Timer

  // Security constants - reasonable limits that don't break functionality
  private let MAX_MINERS_PER_USER: Nat = 1000; // Very generous limit
  private let MAX_TOTAL_MINERS: Nat = 100000; // High limit to avoid breaking functionality
  private let MAX_MINER_NAME_LENGTH: Nat = 200; // Generous name length
  private let MIN_CYCLES_REQUIRED: Nat = 1_000_000_000_000; // 1T cycles minimum

  // Safe arithmetic helper function to prevent traps
  private func safeSub(a: Nat, b: Nat) : Nat {
    if (a >= b) { a - b } else { 0 }
  };

  // Stable variables for upgrade safety
  private stable var stableCurrentRound: Nat = 0;
  private stable var stableLastBlockTime: Int = 0;
  private stable var stableTotalMinersCreated: Nat = 0;
  private stable var stableMinersData: [(Nat, Miner)] = [];
  private stable var stableUserMinersData: [(Principal, [Nat])] = [];
  private stable var stableMiningRounds: [MiningRound] = [];
  
  // Leaderboard stable variables
  private stable var stableLeaderboardData: [(Principal, LeaderboardEntry)] = [];
  private stable var stableTotalRewardsPaid: Nat = 0;
  
  // Optimized leaderboard cache stable variables
  private stable var stableCachedByWins: [LeaderboardEntry] = [];
  private stable var stableCachedByRewards: [LeaderboardEntry] = [];
  private stable var stableCachedByStreak: [LeaderboardEntry] = [];
  private stable var stableLastCacheUpdate: Int = 0;
  private stable var stableCacheIsDirty: Bool = true;

  // Contract state - will be restored from stable variables
  private var currentRound: Nat = stableCurrentRound;
  private var lastBlockTime: Int = if (stableLastBlockTime == 0) Time.now() else stableLastBlockTime;
  private var totalMinersCreated: Nat = stableTotalMinersCreated;
  
  // Miners storage - each user can have multiple miners
  private var miners = HashMap.HashMap<Nat, Miner>(50, Nat.equal, func(id: Nat) : Nat32 { Nat32.fromNat(id % (2**32)) });
  private var userMiners = HashMap.HashMap<Principal, [Nat]>(20, Principal.equal, Principal.hash);
  private var miningRounds: [MiningRound] = stableMiningRounds;
  
  // Leaderboard storage
  private var leaderboard = HashMap.HashMap<Principal, LeaderboardEntry>(20, Principal.equal, Principal.hash);
  private var totalRewardsPaidGlobal: Nat = stableTotalRewardsPaid;
  
  // Optimized leaderboard cache - runtime variables
  private var cachedByWins: [LeaderboardEntry] = stableCachedByWins;
  private var cachedByRewards: [LeaderboardEntry] = stableCachedByRewards;
  private var cachedByStreak: [LeaderboardEntry] = stableCachedByStreak;
  private var lastCacheUpdate: Int = stableLastCacheUpdate;
  private var cacheIsDirty: Bool = stableCacheIsDirty;
  
  // Cache refresh interval (5 minutes = 300 seconds)
  private let CACHE_REFRESH_INTERVAL: Int = 300 * 1_000_000_000;

  // Initialize from stable state
  private func initializeFromStable() {
    for ((id, miner) in stableMinersData.vals()) {
      miners.put(id, miner);
    };
    for ((user, minerIds) in stableUserMinersData.vals()) {
      userMiners.put(user, minerIds);
    };
    for ((user, entry) in stableLeaderboardData.vals()) {
      leaderboard.put(user, entry);
    };
  };

  // Call initialization
  initializeFromStable();
  
  // Initialize mining canister principal on first run
  if (miningCanisterPrincipal == null) {
    miningCanisterPrincipal := ?Principal.fromActor(Mining);
    Debug.print("First run: Initialized mining canister principal: " # Principal.toText(Option.get(miningCanisterPrincipal, Principal.fromText("aaaaa-aa"))));
  };

  // ===============================
  // SIWE Provider (ic_siwe_provider) Integration
  // ===============================
  private stable var siweProvider : ?Principal = null; // set by admin

  // Partial SIWE interface
  type SiweGetAddressResponse = { #Ok : Text; #Err : Text };
  type SiweGetPrincipalResponse = { #Ok : Blob; #Err : Text };
  type SiweProvider = actor {
    get_address : (Blob) -> async SiweGetAddressResponse;
    get_principal : (Text) -> async SiweGetPrincipalResponse;
  };

  private func siweActor() : ?SiweProvider {
    switch (siweProvider) {
      case null null;
      case (?p) ?(actor (Principal.toText(p)) : SiweProvider);
    }
  };

  // Resolve the stable Principal tied to the caller's ETH address
  private func stablePrincipalForCaller(caller : Principal) : async Result.Result<Principal, Text> {
    switch (siweActor()) {
      case null { return #err("SIWE provider not configured"); };
      case (?sp) {
        let addrResp = await sp.get_address(Principal.toBlob(caller));
        let eth = switch (addrResp) { case (#Ok(a)) a; case (#Err(e)) return #err("Auth failed: " # e) };
        let princResp = await sp.get_principal(eth);
        switch (princResp) {
          case (#Ok(blob)) { #ok(Principal.fromBlob(blob)) };
          case (#Err(e)) { #err("Stable principal error: " # e) };
        }
      };
    }
  };
  
  // Helper function to get mining canister principal
  private func getMiningCanisterPrincipal(): Principal {
    switch (miningCanisterPrincipal) {
      case (?principal) principal;
      case null {
        // Fallback initialization if somehow not set
        let principal = Principal.fromActor(Mining);
        miningCanisterPrincipal := ?principal;
        principal;
      };
    }
  };

  // Data types
  public type Miner = {
    id: Nat;
    owner: Principal;
    name: Text;
    miningPower: Nat; // Custom metadata for display/future features
    dailyDirtRate: Nat; // DIRT consumed per day (1-10 billion)
    dirtBalance: Nat; // Current DIRT balance in this miner
    isActive: Bool;
    createdAt: Int;
    lastActiveBlock: Nat;
  };

  public type MiningRound = {
    roundId: Nat;
    startTime: Int;
    endTime: Int;
    isCompleted: Bool;
    winner: ?Principal;
    winnerMiner: ?Nat;
    totalActiveMiners: Nat;
    totalDirtConsumed: Nat;
    rewardsPaid: Nat;
    randomSeed: ?Blob;
  };

  public type MinerCreationArgs = {
    name: Text;
    miningPower: Nat;
    dailyDirtRate: Nat;
    initialDirtAmount: Nat;
  };

  public type MinerError = {
    #InvalidDirtRate: Text;
    #InsufficientFunds: Text;
    #MinerNotFound: Text;
    #NotAuthorized: Text;
    #TransferError: ICRCToken.TransferFromError;
    #InvalidInput: Text;
    #SystemError: Text;
  };

  // Leaderboard data types
  public type LeaderboardEntry = {
    user: Principal;
    totalWins: Nat;
    totalRewards: Nat;
    lastWinRound: Nat;
    lastWinTime: Int;
    winStreak: Nat;
    longestWinStreak: Nat;
  };

  public type LeaderboardStats = {
    topWinners: [LeaderboardEntry];
    totalUniqueWinners: Nat;
    totalRewardsPaid: Nat;
    lastUpdated: Int;
  };

  // --- Upgrade Hooks for State Persistence ---
  
  system func preupgrade() {
    stableCurrentRound := currentRound;
    stableLastBlockTime := lastBlockTime;
    stableTotalMinersCreated := totalMinersCreated;
    stableMinersData := Iter.toArray(miners.entries());
    stableUserMinersData := Iter.toArray(userMiners.entries());
    stableMiningRounds := miningRounds;
    stableLeaderboardData := Iter.toArray(leaderboard.entries());
    stableTotalRewardsPaid := totalRewardsPaidGlobal;
    
    // Save optimized cache data
    stableCachedByWins := cachedByWins;
    stableCachedByRewards := cachedByRewards;
    stableCachedByStreak := cachedByStreak;
    stableLastCacheUpdate := lastCacheUpdate;
    stableCacheIsDirty := cacheIsDirty;
    
    Debug.print("Pre-upgrade: Saved " # Nat.toText(miners.size()) # " miners, " # Nat.toText(miningRounds.size()) # " rounds, " # Nat.toText(leaderboard.size()) # " leaderboard entries, and " # Nat.toText(cachedByWins.size()) # " cached entries");
  };

  system func postupgrade() {
    // State is already restored during initialization
    initializeFromStable(); // Ensure proper restoration
    
    // Initialize mining canister principal if not set
    if (miningCanisterPrincipal == null) {
      miningCanisterPrincipal := ?Principal.fromActor(Mining);
      Debug.print("Initialized mining canister principal: " # Principal.toText(Option.get(miningCanisterPrincipal, Principal.fromText("aaaaa-aa"))));
    };
    
    // Auto-refresh cache if it's old or dirty
    refreshCacheIfNeeded();
    
    Debug.print("Post-upgrade: Restored " # Nat.toText(miners.size()) # " miners, " # Nat.toText(miningRounds.size()) # " rounds, " # Nat.toText(leaderboard.size()) # " leaderboard entries, and " # Nat.toText(cachedByWins.size()) # " cached entries");
  };

  // --- Security & Validation Functions ---
  
  private func validateMinerCreationArgs(args: MinerCreationArgs): Result.Result<(), MinerError> {
    // Name validation - generous limits to not break functionality
    if (args.name.size() == 0) {
      return #err(#InvalidInput("Miner name cannot be empty"));
    };
    if (args.name.size() > MAX_MINER_NAME_LENGTH) {
      return #err(#InvalidInput("Miner name too long (max " # Nat.toText(MAX_MINER_NAME_LENGTH) # " characters)"));
    };
    
    // Mining power validation - prevent unreasonable values
    if (args.miningPower == 0) {
      return #err(#InvalidInput("Mining power must be greater than 0"));
    };
    if (args.miningPower > 1_000_000_000) { // 1 billion max - very generous
      return #err(#InvalidInput("Mining power too high"));
    };
    
    // Daily DIRT rate validation (existing logic)
    if (args.dailyDirtRate < MIN_DAILY_DIRT_RATE or args.dailyDirtRate > MAX_DAILY_DIRT_RATE) {
      return #err(#InvalidDirtRate("Daily DIRT rate must be between " # Nat.toText(MIN_DAILY_DIRT_RATE) # " and " # Nat.toText(MAX_DAILY_DIRT_RATE)));
    };
    
    // Initial DIRT amount validation (existing logic)
    if (args.initialDirtAmount < args.dailyDirtRate) {
      return #err(#InsufficientFunds("Initial DIRT amount must cover at least 1 day of mining"));
    };
    
    #ok(())
  };
  
  private func checkCycles(): Bool {
    Cycles.balance() > MIN_CYCLES_REQUIRED
  };
  
  private func checkMinerLimits(caller: Principal): Result.Result<(), MinerError> {
    // Check total miners limit - very generous to not break functionality
    if (totalMinersCreated >= MAX_TOTAL_MINERS) {
      return #err(#SystemError("System has reached maximum capacity. Please try again later."));
    };
    
    // Check per-user limit - very generous
    let currentUserMiners = Option.get(userMiners.get(caller), []);
    if (currentUserMiners.size() >= MAX_MINERS_PER_USER) {
      return #err(#SystemError("You have reached the maximum number of miners per user."));
    };
    
    #ok(())
  };

  // --- Miner Creation & Management ---
  
  public shared (msg) func createMiner(args: MinerCreationArgs): async Result.Result<Nat, MinerError> {
    let caller = msg.caller;
    
    // Security validations
    switch (validateMinerCreationArgs(args)) {
      case (#err(e)) return #err(e);
      case (#ok(())) {};
    };
    
    switch (checkMinerLimits(caller)) {
      case (#err(e)) return #err(e);
      case (#ok(())) {};
    };
    
    // Check cycles before expensive operations
    if (not checkCycles()) {
      return #err(#SystemError("System temporarily unavailable due to low cycles"));
    };
    
    // Resolve user's stable principal (derived from ETH)
    let userStable = switch (await stablePrincipalForCaller(caller)) {
      case (#ok(p)) p;
      case (#err(e)) return #err(#SystemError("SIWE authentication required: " # e));
    };

    // Transfer DIRT from user's STABLE principal to this canister using ICRC-2 (requires prior approve)
    type DirtActor = actor {
      icrc1_fee : shared query () -> async ICRCToken.Tokens;
      icrc2_transfer_from : shared ({
        spender_subaccount : ?ICRCToken.Subaccount;
        from : ICRCToken.Account;
        to : ICRCToken.Account;
        amount : ICRCToken.Tokens;
        fee : ?ICRCToken.Tokens;
        memo : ?ICRCToken.Memo;
        created_at_time : ?ICRCToken.Timestamp;
      }) -> async Result.Result<ICRCToken.TxIndex, ICRCToken.TransferFromError>;
    };
    let dirtToken: DirtActor = actor (Principal.toText(dirtTokenCanister));
    
    // Get fee with error handling
    let fee = try {
      await dirtToken.icrc1_fee()
    } catch (_) {
      Debug.print("Failed to get DIRT token fee: Inter-canister call failed");
      return #err(#SystemError("Unable to connect to DIRT token. Please try again."));
    };
    
    let transferResult = try {
      await dirtToken.icrc2_transfer_from({
        spender_subaccount = null;
        // Pull from the user's STABLE principal (requires user approval to this canister)
        from = { owner = userStable; subaccount = null };
        to = { owner = getMiningCanisterPrincipal(); subaccount = null };
        amount = args.initialDirtAmount;
        fee = ?fee;
        memo = null;
        created_at_time = null;
      })
    } catch (_) {
      Debug.print("DIRT transfer failed with exception: Inter-canister call failed");
      return #err(#SystemError("Transfer failed. Please ensure you have approved the spending amount."));
    };
    
    switch (transferResult) {
      case (#ok(_blockHeight)) {
        // Create new miner
        totalMinersCreated += 1;
        let minerId = totalMinersCreated;
        
        let newMiner: Miner = {
          id = minerId;
          owner = userStable; // store stable principal as owner
          name = args.name;
          miningPower = args.miningPower;
          dailyDirtRate = args.dailyDirtRate;
          dirtBalance = args.initialDirtAmount;
          isActive = true;
          createdAt = Time.now();
          lastActiveBlock = currentRound;
        };
        
        // Store miner
        miners.put(minerId, newMiner);
        
        // Add to user's miner list
        let currentUserMiners = Option.get(userMiners.get(userStable), []);
        userMiners.put(userStable, Array.append(currentUserMiners, [minerId]));
        
        Debug.print("Miner created: ID=" # Nat.toText(minerId) # ", Owner=" # Principal.toText(caller) # ", DIRT=" # Nat.toText(args.initialDirtAmount));
        return #ok(minerId);
      };
      case (#err(e)) return #err(#TransferError(e));
    };
  };
  
  public shared (msg) func topUpMiner(minerId: Nat, amount: Nat): async Result.Result<Bool, MinerError> {
    let caller = msg.caller;
    
    // Basic input validation
    if (amount == 0) {
      return #err(#InvalidInput("Top-up amount must be greater than 0"));
    };
    
    let miner = switch (miners.get(minerId)) {
      case (?m) m;
      case null return #err(#MinerNotFound("Miner not found"));
    };
    
    // Map caller to stable principal
    let userStable = switch (await stablePrincipalForCaller(caller)) {
      case (#ok(p)) p;
      case (#err(e)) return #err(#SystemError("SIWE authentication required: " # e));
    };

    if (miner.owner != userStable) {
      return #err(#NotAuthorized("Only miner owner can top up"));
    };
    
    // Check cycles before expensive operations
    if (not checkCycles()) {
      return #err(#SystemError("System temporarily unavailable due to low cycles"));
    };
    
    // Transfer DIRT from user to this canister using production-grade token
    type DirtActor = actor {
      icrc1_fee : shared query () -> async ICRCToken.Tokens;
      icrc2_transfer_from : shared ({
        spender_subaccount : ?ICRCToken.Subaccount;
        from : ICRCToken.Account;
        to : ICRCToken.Account;
        amount : ICRCToken.Tokens;
        fee : ?ICRCToken.Tokens;
        memo : ?ICRCToken.Memo;
        created_at_time : ?ICRCToken.Timestamp;
      }) -> async Result.Result<ICRCToken.TxIndex, ICRCToken.TransferFromError>;
    };
    let dirtToken: DirtActor = actor (Principal.toText(dirtTokenCanister));
    
    // Get fee with error handling
    let fee = try {
      await dirtToken.icrc1_fee()
    } catch (_) {
      Debug.print("Failed to get DIRT token fee: Inter-canister call failed");
      return #err(#SystemError("Unable to connect to DIRT token. Please try again."));
    };
    
    let transferResult = try {
      await dirtToken.icrc2_transfer_from({
        spender_subaccount = null;
        from = { owner = userStable; subaccount = null };
        to = { owner = getMiningCanisterPrincipal(); subaccount = null };
        amount = amount;
        fee = ?fee;
        memo = null;
        created_at_time = null;
      })
    } catch (_) {
      Debug.print("DIRT transfer failed with exception: Inter-canister call failed");
      return #err(#SystemError("Transfer failed. Please ensure you have approved the spending amount."));
    };
    
    switch (transferResult) {
      case (#ok(_)) {
        // Update miner balance
        let updatedMiner: Miner = {
          id = miner.id;
          owner = miner.owner;
          name = miner.name;
          miningPower = miner.miningPower;
          dailyDirtRate = miner.dailyDirtRate;
          dirtBalance = miner.dirtBalance + amount;
          isActive = miner.isActive;
          createdAt = miner.createdAt;
          lastActiveBlock = miner.lastActiveBlock;
        };
        miners.put(minerId, updatedMiner);
        
        Debug.print("Miner topped up: ID=" # Nat.toText(minerId) # ", Amount=" # Nat.toText(amount));
        return #ok(true);
      };
      case (#err(e)) return #err(#TransferError(e));
    };
  };
  
  public shared (msg) func pauseMiner(minerId: Nat): async Result.Result<Bool, MinerError> {
    let caller = msg.caller;
    
    let miner = switch (miners.get(minerId)) {
      case (?m) m;
      case null return #err(#MinerNotFound("Miner not found"));
    };
    
    let userStable = switch (await stablePrincipalForCaller(caller)) {
      case (#ok(p)) p;
      case (#err(e)) return #err(#SystemError("SIWE authentication required: " # e));
    };
    if (miner.owner != userStable) {
      return #err(#NotAuthorized("Only miner owner can pause"));
    };
    
    let updatedMiner: Miner = {
      id = miner.id;
      owner = miner.owner;
      name = miner.name;
      miningPower = miner.miningPower;
      dailyDirtRate = miner.dailyDirtRate;
      dirtBalance = miner.dirtBalance;
      isActive = false;
      createdAt = miner.createdAt;
      lastActiveBlock = miner.lastActiveBlock;
    };
    miners.put(minerId, updatedMiner);
    
    return #ok(true);
  };
  
  public shared (msg) func resumeMiner(minerId: Nat): async Result.Result<Bool, MinerError> {
    let caller = msg.caller;
    
    let miner = switch (miners.get(minerId)) {
      case (?m) m;
      case null return #err(#MinerNotFound("Miner not found"));
    };
    
    let userStable = switch (await stablePrincipalForCaller(caller)) {
      case (#ok(p)) p;
      case (#err(e)) return #err(#SystemError("SIWE authentication required: " # e));
    };
    if (miner.owner != userStable) {
      return #err(#NotAuthorized("Only miner owner can resume"));
    };
    
    let updatedMiner: Miner = {
      id = miner.id;
      owner = miner.owner;
      name = miner.name;
      miningPower = miner.miningPower;
      dailyDirtRate = miner.dailyDirtRate;
      dirtBalance = miner.dirtBalance;
      isActive = true;
      createdAt = miner.createdAt;
      lastActiveBlock = miner.lastActiveBlock;
    };
    miners.put(minerId, updatedMiner);
    
    return #ok(true);
  };

  // Edit miner properties (owner only)
  public shared (msg) func editMiner(
    minerId: Nat,
    newName: ?Text,
    newDailyDirtRate: ?Nat,
    newMiningPower: ?Nat
  ): async Result.Result<Bool, MinerError> {
    let caller = msg.caller;
    
    let miner = switch (miners.get(minerId)) {
      case (?m) m;
      case null return #err(#MinerNotFound("Miner not found"));
    };
    
    let userStable = switch (await stablePrincipalForCaller(caller)) {
      case (#ok(p)) p;
      case (#err(e)) return #err(#SystemError("SIWE authentication required: " # e));
    };
    if (miner.owner != userStable) {
      return #err(#NotAuthorized("Only miner owner can edit"));
    };
    
    // Validate new name if provided
    let finalName = switch (newName) {
      case (?name) {
        if (name.size() == 0) {
          return #err(#InvalidInput("Miner name cannot be empty"));
        };
        if (name.size() > MAX_MINER_NAME_LENGTH) {
          return #err(#InvalidInput("Miner name too long (max " # Nat.toText(MAX_MINER_NAME_LENGTH) # " characters)"));
        };
        name
      };
      case null miner.name;
    };
    
    // Validate new daily DIRT rate if provided
    let finalDailyDirtRate = switch (newDailyDirtRate) {
      case (?rate) {
        if (rate < MIN_DAILY_DIRT_RATE or rate > MAX_DAILY_DIRT_RATE) {
          return #err(#InvalidDirtRate("Daily DIRT rate must be between " # Nat.toText(MIN_DAILY_DIRT_RATE) # " and " # Nat.toText(MAX_DAILY_DIRT_RATE)));
        };
        rate
      };
      case null miner.dailyDirtRate;
    };
    
    // Validate new mining power if provided
    let finalMiningPower = switch (newMiningPower) {
      case (?power) {
        if (power == 0) {
          return #err(#InvalidInput("Mining power must be greater than 0"));
        };
        if (power > 1_000_000_000) { // 1 billion max - very generous
          return #err(#InvalidInput("Mining power too high"));
        };
        power
      };
      case null miner.miningPower;
    };
    
    // Update miner with new values
    let updatedMiner: Miner = {
      id = miner.id;
      owner = miner.owner;
      name = finalName;
      miningPower = finalMiningPower;
      dailyDirtRate = finalDailyDirtRate;
      dirtBalance = miner.dirtBalance;
      isActive = miner.isActive;
      createdAt = miner.createdAt;
      lastActiveBlock = miner.lastActiveBlock;
    };
    miners.put(minerId, updatedMiner);
    
    Debug.print("Miner edited: ID=" # Nat.toText(minerId) # ", Owner=" # Principal.toText(caller) # ", Name=" # finalName # ", DailyRate=" # Nat.toText(finalDailyDirtRate) # ", Power=" # Nat.toText(finalMiningPower));
    return #ok(true);
  };

//---------------------------
  // --- Leaderboard Management ---
  
  private func updateLeaderboard(winner: Principal, rewardAmount: Nat, roundId: Nat) {
    let now = Time.now();
    totalRewardsPaidGlobal += rewardAmount;
    
    switch (leaderboard.get(winner)) {
      case (?existingEntry) {
        // Update existing entry - use safe arithmetic to prevent underflow
        let isConsecutiveWin = roundId > 0 and existingEntry.lastWinRound == (roundId - 1);
        let newWinStreak = if (isConsecutiveWin) { existingEntry.winStreak + 1 } else { 1 };
        let newLongestStreak = Nat.max(existingEntry.longestWinStreak, newWinStreak);
        
        let updatedEntry: LeaderboardEntry = {
          user = winner;
          totalWins = existingEntry.totalWins + 1;
          totalRewards = existingEntry.totalRewards + rewardAmount;
          lastWinRound = roundId;
          lastWinTime = now;
          winStreak = newWinStreak;
          longestWinStreak = newLongestStreak;
        };
        leaderboard.put(winner, updatedEntry);
      };
      case null {
        // Create new entry
        let newEntry: LeaderboardEntry = {
          user = winner;
          totalWins = 1;
          totalRewards = rewardAmount;
          lastWinRound = roundId;
          lastWinTime = now;
          winStreak = 1;
          longestWinStreak = 1;
        };
        leaderboard.put(winner, newEntry);
      };
    };
    
    // Mark cache as dirty for refresh (optimization)
    cacheIsDirty := true;
  };

  // Refresh cache only when needed - prevents expensive operations
  private func refreshCacheIfNeeded() {
    let now = Time.now();
    
    // Only refresh if cache is dirty and enough time has passed
    if (cacheIsDirty and (now - lastCacheUpdate) > CACHE_REFRESH_INTERVAL) {
      refreshLeaderboardCache();
    };
  };

  // Expensive operation - only called when absolutely necessary
  private func refreshLeaderboardCache() {
    var entries: [LeaderboardEntry] = [];
    
    // Convert HashMap to Array (expensive)
    for ((user, entry) in leaderboard.entries()) {
      entries := Array.append(entries, [entry]);
    };
    
    // Sort by wins (cache result)
    cachedByWins := Array.sort(entries, func(a: LeaderboardEntry, b: LeaderboardEntry) : Order.Order {
      if (a.totalWins > b.totalWins) { #less }
      else if (a.totalWins < b.totalWins) { #greater }
      else if (a.totalRewards > b.totalRewards) { #less }
      else if (a.totalRewards < b.totalRewards) { #greater }
      else { #equal }
    });
    
    // Sort by rewards (cache result)
    cachedByRewards := Array.sort(entries, func(a: LeaderboardEntry, b: LeaderboardEntry) : Order.Order {
      if (a.totalRewards > b.totalRewards) { #less }
      else if (a.totalRewards < b.totalRewards) { #greater }
      else if (a.totalWins > b.totalWins) { #less }
      else if (a.totalWins < b.totalWins) { #greater }
      else { #equal }
    });
    
    // Sort by streak (cache result)
    cachedByStreak := Array.sort(entries, func(a: LeaderboardEntry, b: LeaderboardEntry) : Order.Order {
      if (a.winStreak > b.winStreak) { #less }
      else if (a.winStreak < b.winStreak) { #greater }
      else if (a.totalWins > b.totalWins) { #less }
      else if (a.totalWins < b.totalWins) { #greater }
      else { #equal }
    });
    
    lastCacheUpdate := Time.now();
    cacheIsDirty := false;
    
    Debug.print("Leaderboard cache refreshed with " # Nat.toText(entries.size()) # " entries");
  };

  // --- Mining Block Logic ---
  
  private func calculateDirtForBlock(dailyRate: Nat): Nat {
    // Calculate DIRT consumed per block based on daily rate and block duration
    // dailyRate is in DIRT per day, convert to per-block based on 686 seconds per block
    let secondsPerDay: Nat = 86400; // 24 * 60 * 60
    let dirtPerSecond = dailyRate / secondsPerDay;
    dirtPerSecond * BLOCK_DURATION_SECONDS
  };
  
  private func getActiveMiners(): [(Nat, Miner)] {
    var activeMiners: [(Nat, Miner)] = [];
    for ((minerId, miner) in miners.entries()) {
      if (miner.isActive) {
        let dirtNeeded = calculateDirtForBlock(miner.dailyDirtRate);
        if (miner.dirtBalance >= dirtNeeded) {
          activeMiners := Array.append(activeMiners, [(minerId, miner)]);
        };
      };
    };
    activeMiners
  };
  
  private func updateMinerAfterBlock(minerId: Nat, miner: Miner, dirtConsumed: Nat, _won: Bool): Miner {
    // Use safe subtraction to prevent arithmetic traps
    let newBalance = safeSub(miner.dirtBalance, dirtConsumed);
    
    {
      id = miner.id;
      owner = miner.owner;
      name = miner.name;
      miningPower = miner.miningPower;
      dailyDirtRate = miner.dailyDirtRate;
      dirtBalance = newBalance;
      isActive = newBalance > 0; // Auto-pause if no DIRT left
      createdAt = miner.createdAt;
      lastActiveBlock = currentRound;
    }
};

  // Helper function to get lifetime wins for a specific miner
  private func calculateMinerLifetimeWins(minerId: Nat): Nat {
    var wins: Nat = 0;
    for (round in miningRounds.vals()) {
      switch (round.winnerMiner) {
        case (?winnerMinerId) {
          if (winnerMinerId == minerId) {
            wins += 1;
          };
        };
        case null {};
      };
    };
    wins
  };

  // --- Helper Functions ---
  
  // Weighted random miner selection where probability ∝ DIRT spent this block
  private func selectRandomWinnerMiner(activeMiners: [(Nat, Miner)], randBlob: Blob) : ?(Nat, Principal) {
    if (activeMiners.size() == 0) return null;

    // Sort by minerId for deterministic cumulative traversal
    let sortedMiners = Array.sort<(Nat, Miner)>(activeMiners, func(a: (Nat, Miner), b: (Nat, Miner)) : Order.Order {
      let (aId, _) = a;
      let (bId, _) = b;
      if (aId < bId) { #less } else if (aId > bId) { #greater } else { #equal }
    });

    // DEBUG: Log the random blob and active miners
    Debug.print("=== WINNER SELECTION DEBUG ===");
    Debug.print("Active miners count: " # Nat.toText(sortedMiners.size()));
    Debug.print("Random blob size: " # Nat.toText(randBlob.size()));

    // Print all active miner IDs
    var minerIdsText = "Active miner IDs: [";
    for (i in Iter.range(0, safeSub(sortedMiners.size(), 1))) {
      let (minerId, _) = sortedMiners[i];
      minerIdsText := minerIdsText # Nat.toText(minerId);
      if (sortedMiners.size() > 0 and i < sortedMiners.size() - 1) {
        minerIdsText := minerIdsText # ", ";
      };
    };
    minerIdsText := minerIdsText # "]";
    Debug.print(minerIdsText);

    // Compute per-miner weights (DIRT spent this block) and total weight D
    var totalWeight: Nat = 0;
    var weightsText = "Weights per miner (DIRT/block): [";
    for (i in Iter.range(0, safeSub(sortedMiners.size(), 1))) {
      let (_, miner) = sortedMiners[i];
      let w = calculateDirtForBlock(miner.dailyDirtRate);
      totalWeight += w;
      weightsText := weightsText # Nat.toText(w);
      if (i < sortedMiners.size() - 1) { weightsText := weightsText # ", "; };
    };
    weightsText := weightsText # "]";
    Debug.print(weightsText);
    Debug.print("Total weight (D): " # Nat.toText(totalWeight));

    if (totalWeight == 0) {
      // Fallback safety: if all weights are zero, revert to equal probability
      let randBytesEq = Blob.toArray(randBlob);
      var randomEq: Nat = 0;
      for (b in randBytesEq.vals()) { randomEq := randomEq * 256 + Nat8.toNat(b) };
      let idx = randomEq % sortedMiners.size();
      let (fallbackId, fallbackMiner) = sortedMiners[idx];
      Debug.print("Weights are zero; falling back to equal selection. Winner miner ID " # Nat.toText(fallbackId));
      Debug.print("=== END DEBUG ===");
      return ?(fallbackId, fallbackMiner.owner);
    };

    // Convert full blob to a large Nat for randomness
    let randBytes = Blob.toArray(randBlob);
    var randomValue: Nat = 0;
    for (b in randBytes.vals()) {
      randomValue := randomValue * 256 + Nat8.toNat(b);
    };
    Debug.print("Computed randomValue: " # Nat.toText(randomValue));

    // Draw a target position on the cumulative line [0, D)
    let target = randomValue % totalWeight;
    Debug.print("Computed target on cumulative line: " # Nat.toText(target));

    // Walk cumulative weights to locate winner
    var cumulative: Nat = 0;
    var winner: ?(Nat, Principal) = null;
    label L for (i in Iter.range(0, safeSub(sortedMiners.size(), 1))) {
      let (minerId, miner) = sortedMiners[i];
      let w = calculateDirtForBlock(miner.dailyDirtRate);
      if (target < cumulative + w) {
        Debug.print("Selected winner: Miner ID " # Nat.toText(minerId));
        winner := ?(minerId, miner.owner);
        break L;
      };
      cumulative += w;
    };

    Debug.print("=== END DEBUG ===");
    winner
  };
  
  // Function to burn DIRT tokens by sending to burn address
  private func burnDirt(amount: Nat) : async Bool {
    if (amount == 0) return true;
    
    // Check cycles before expensive operations
    if (not checkCycles()) {
      Debug.print("Low cycles, skipping DIRT burn");
      return false;
    };
    
    type DirtActor = actor {
      icrc1_fee : shared query () -> async ICRCToken.Tokens;
      icrc1_transfer : shared ({
        from_subaccount : ?ICRCToken.Subaccount;
        to : ICRCToken.Account;
        amount : ICRCToken.Tokens;
        fee : ?ICRCToken.Tokens;
        memo : ?ICRCToken.Memo;
        created_at_time : ?ICRCToken.Timestamp;
      }) -> async Result.Result<ICRCToken.TxIndex, ICRCToken.TransferError>;
    };
    let dirtToken: DirtActor = actor (Principal.toText(dirtTokenCanister));
    
    // Get fee with error handling
    let fee = try {
      await dirtToken.icrc1_fee()
    } catch (_) {
      Debug.print("Failed to get DIRT token fee for burn: Inter-canister call failed");
      return false;
    };
    
    // Use safe subtraction to prevent arithmetic traps
    let burnAmount = safeSub(amount, fee);
    
    if (burnAmount == 0) return false;
    
    let burnResult = try {
      await dirtToken.icrc1_transfer({
        from_subaccount = null;
        to = { owner = BURN_ADDRESS; subaccount = null };
        amount = burnAmount;
        fee = ?fee;
        memo = null;
        created_at_time = null;
      })
    } catch (_) {
      Debug.print("DIRT burn failed with exception: Inter-canister call failed");
      return false;
    };
    
    switch (burnResult) {
      case (#ok(_)) {
        Debug.print("Successfully burned " # Nat.toText(burnAmount) # " DIRT");
        true;
      };
      case (#err(_)) {
        Debug.print("DIRT burn failed: Transfer error occurred");
        false;
      };
    }
  };

  // --- Mining Block Production ---

  public shared (msg) func mineBlock(): async Text {
    // Only owner or automated timer can trigger block mining
    if (msg.caller != owner) {
      return "Only owner can manually trigger block mining.";
    };
    
    ignore await processBlock();
    return "Block processed successfully.";
  };

  private func processBlock(): async Text {
    let now = Time.now();
    
    // Get all active miners that can participate in this block
    let activeMiners = getActiveMiners();
    
    if (activeMiners.size() == 0) {
      Debug.print("No active miners for block " # Nat.toText(currentRound + 1));
      return "No active miners.";
    };

    // Generate randomness for winner selection
    let randBlob = await Random.blob();
    
    // Select winner miner completely randomly (equal probability)
    let winnerResult = selectRandomWinnerMiner(activeMiners, randBlob);
    
    var totalDirtConsumed: Nat = 0;
    var totalDirtToBurn: Nat = 0;
    var winnerMinerId: ?Nat = null;
    var winnerPrincipal: ?Principal = null;
    
    // Process all miners - consume DIRT and update states
    for ((minerId, miner) in activeMiners.vals()) {
      let dirtForBlock = calculateDirtForBlock(miner.dailyDirtRate);
      totalDirtConsumed += dirtForBlock;
      
      let isWinner = switch (winnerResult) {
        case (?(wId, _)) wId == minerId;
        case null false;
      };
      
      if (isWinner) {
        winnerMinerId := ?minerId;
        winnerPrincipal := ?miner.owner;
        Debug.print("Block winner: Miner ID " # Nat.toText(minerId) # " owned by " # Principal.toText(miner.owner));
      };
      totalDirtToBurn += dirtForBlock;
      
      
      let updatedMiner = updateMinerAfterBlock(minerId, miner, dirtForBlock, isWinner);
      miners.put(minerId, updatedMiner);
    };
    
    // Burn DIRT from non-winning miners
    if (totalDirtToBurn > 0) {
      let burnSuccess = await burnDirt(totalDirtToBurn);
      if (burnSuccess) {
        Debug.print("Burned " # Nat.toText(totalDirtToBurn) # " DIRT from " # Nat.toText(safeSub(activeMiners.size(), 1)) # " non-winning miners");
      } else {
        Debug.print("Failed to burn DIRT");
      };
    };

    // Pay reward to winner
    var rewardsPaid: Nat = 0;
    switch (winnerPrincipal) {
      case (?winner) {
        // Check cycles before expensive mint operation
        if (checkCycles()) {
          // AK69 token with production-grade mint function
          type AK69Actor = actor {
            admin_mint : shared (to : ICRCToken.Account, amount : ICRCToken.Tokens) -> async Result.Result<ICRCToken.TxIndex, Text>;
          };
          
          let ak69Token: AK69Actor = actor (Principal.toText(ak69TokenCanister));
          let winnerAccount: ICRCToken.Account = { owner = winner; subaccount = null };
          
          let mintResult = try {
            await ak69Token.admin_mint(winnerAccount, BLOCK_REWARD)
          } catch (_) {
            Debug.print("Failed to mint AK69 reward (exception): Inter-canister call failed");
            #err("Mint operation failed")
          };
        
          switch (mintResult) {
            case (#ok(txId)) {
              rewardsPaid := BLOCK_REWARD;
              // Update leaderboard for winner
              updateLeaderboard(winner, BLOCK_REWARD, currentRound + 1);
              // Force cache refresh immediately after leaderboard update
              refreshLeaderboardCache();
              Debug.print("Block " # Nat.toText(currentRound + 1) # " winner: " # Principal.toText(winner) # ", reward: " # Nat.toText(BLOCK_REWARD) # " AK69, tx: " # Nat.toText(txId));
            };
            case (#err(e)) {
              Debug.print("Failed to mint reward: " # e);
            };
          };
        } else {
          Debug.print("Low cycles, skipping reward mint for winner: " # Principal.toText(winner));
        };
      };
      case null {
        Debug.print("No winner selected for block " # Nat.toText(currentRound + 1));
      };
    };

    // Create mining round record
    currentRound += 1;
    let newRound: MiningRound = {
      roundId = currentRound;
      startTime = lastBlockTime;
      endTime = now;
      isCompleted = true;
      winner = winnerPrincipal;
      winnerMiner = winnerMinerId;
      totalActiveMiners = activeMiners.size();
      totalDirtConsumed = totalDirtConsumed;
      rewardsPaid = rewardsPaid;
      randomSeed = ?randBlob;
    };
    miningRounds := Array.append(miningRounds, [newRound]);
    lastBlockTime := now;

    // Force cache refresh to ensure leaderboard is updated
    if (cacheIsDirty) {
      refreshLeaderboardCache();
    };
    
    let resultMsg = switch (winnerPrincipal) {
      case (?winner) "Block " # Nat.toText(currentRound) # " mined! Winner: " # Principal.toText(winner);
      case null "Block " # Nat.toText(currentRound) # " processed with no winner.";
    };
    
    return resultMsg;
  };

  // --- Block Timing & Automation ---
  
  private func tryMineBlock() : async () {
  let now = Time.now();
    
    // Check if enough time has passed for next block (11.429 minutes)
    if (now - lastBlockTime >= BLOCK_DURATION_NS) {
      ignore await processBlock();
    };
  };

  // Timer for automatic block mining every ~11.429 minutes
  let _ = Timer.recurringTimer<system>(#seconds(BLOCK_DURATION_SECONDS), func () : async () {
    await tryMineBlock();
  });

  // Manual catch-up function for missed blocks
public shared func catch_up() : async Text {
  let now = Time.now();

    if (now - lastBlockTime >= BLOCK_DURATION_NS) {
      return await processBlock();
  } else {
      let timeLeft = (lastBlockTime + BLOCK_DURATION_NS - now) / 1_000_000_000; // Convert to seconds
      return "Next block in " # Int.toText(timeLeft) # " seconds.";
    };
  };





  // --- Query Functions ---
  
  public query func getMiner(minerId: Nat): async ?Miner {
    miners.get(minerId)
  };
  
  public query func getUserMiners(user: Principal): async [Nat] {
    Option.get(userMiners.get(user), [])
  };
  
  // Get user's miners with full details (more efficient than multiple calls)
  public query func getUserMinersDetailed(user: Principal): async [Miner] {
    let minerIds = Option.get(userMiners.get(user), []);
    var userMinerList: [Miner] = [];
    for (id in minerIds.vals()) {
      switch (miners.get(id)) {
        case (?miner) {
          userMinerList := Array.append(userMinerList, [miner]);
        };
        case null {};
      };
    };
    userMinerList
  };
  
  // Get user's mining statistics summary
  public query func getUserStats(user: Principal): async {
    totalMiners: Nat;
    activeMiners: Nat;
    totalDirtBalance: Nat;
    totalMiningPower: Nat;
    totalDailyRate: Nat;
  } {
    let minerIds = Option.get(userMiners.get(user), []);
    var activeCount: Nat = 0;
    var totalDirt: Nat = 0;
    var totalPower: Nat = 0;
    var totalRate: Nat = 0;
    
    for (id in minerIds.vals()) {
      switch (miners.get(id)) {
        case (?miner) {
          if (miner.isActive) activeCount += 1;
          totalDirt += miner.dirtBalance;
          totalPower += miner.miningPower;
          totalRate += miner.dailyDirtRate;
        };
        case null {};
      };
    };
    
    {
      totalMiners = minerIds.size();
      activeMiners = activeCount;
      totalDirtBalance = totalDirt;
      totalMiningPower = totalPower;
      totalDailyRate = totalRate;
    }
  };
  
  // Get user's recent mining wins
  public query func getUserMiningWins(user: Principal, limit: Nat): async [MiningRound] {
    var userWins: [MiningRound] = [];
    var count: Nat = 0;
    let maxLimit = if (limit > 50) { 50 } else { limit }; // Cap at 50 for performance
    
    // Search through rounds from most recent (reverse order)
    let totalRounds = miningRounds.size();
    if (totalRounds == 0) return userWins;
    
    var i: Int = Int.abs(totalRounds) - 1;
    while (i >= 0 and count < maxLimit) {
      let round = miningRounds[Int.abs(i)];
      switch (round.winner) {
        case (?winner) {
          if (Principal.equal(winner, user)) {
            userWins := Array.append(userWins, [round]);
            count += 1;
          };
        };
        case null {};
      };
      i -= 1;
    };
    
    userWins
  };
  
  // Get lifetime wins for a specific miner (public query)
  public query func getMinerLifetimeWins(minerId: Nat): async Nat {
    var wins: Nat = 0;
    for (round in miningRounds.vals()) {
      switch (round.winnerMiner) {
        case (?winnerMinerId) {
          if (winnerMinerId == minerId) {
            wins += 1;
          };
        };
        case null {};
      };
    };
    wins
  };

  // Get user's complete dashboard data in one call (most efficient)
  public query func getUserDashboard(user: Principal): async {
    miners: [{
      id: Nat;
      owner: Principal;
      name: Text;
      miningPower: Nat;
      dailyDirtRate: Nat;
      dirtBalance: Nat;
      isActive: Bool;
      createdAt: Int;
      lastActiveBlock: Nat;
      lifetimeWins: Nat;
    }];
    stats: {
      totalMiners: Nat;
      activeMiners: Nat;
      totalDirtBalance: Nat;
      totalMiningPower: Nat;
      totalDailyRate: Nat;
    };
    recentWins: [MiningRound];
    winningStats: {
      totalWins: Nat;
      totalRewards: Nat;
      currentWinStreak: Nat;
      longestWinStreak: Nat;
      lastWinRound: ?Nat;
    };
    systemInfo: {
      currentRound: Nat;
      timeToNextBlock: Int;
      blockReward: Nat;
    };
  } {
    // Get user's miners with details and lifetime wins
    let minerIds = Option.get(userMiners.get(user), []);
    var userMinerList: [{
      id: Nat;
      owner: Principal;
      name: Text;
      miningPower: Nat;
      dailyDirtRate: Nat;
      dirtBalance: Nat;
      isActive: Bool;
      createdAt: Int;
      lastActiveBlock: Nat;
      lifetimeWins: Nat;
    }] = [];
    var activeCount: Nat = 0;
    var totalDirt: Nat = 0;
    var totalPower: Nat = 0;
    var totalRate: Nat = 0;
    
    for (id in minerIds.vals()) {
      switch (miners.get(id)) {
        case (?miner) {
          // Calculate lifetime wins for this miner
          let lifetimeWins = calculateMinerLifetimeWins(miner.id);
          
          let minerWithWins = {
            id = miner.id;
            owner = miner.owner;
            name = miner.name;
            miningPower = miner.miningPower;
            dailyDirtRate = miner.dailyDirtRate;
            dirtBalance = miner.dirtBalance;
            isActive = miner.isActive;
            createdAt = miner.createdAt;
            lastActiveBlock = miner.lastActiveBlock;
            lifetimeWins = lifetimeWins;
          };
          
          userMinerList := Array.append(userMinerList, [minerWithWins]);
          if (miner.isActive) activeCount += 1;
          totalDirt += miner.dirtBalance;
          totalPower += miner.miningPower;
          totalRate += miner.dailyDirtRate;
        };
        case null {};
      };
    };
    
    // Get user's recent wins (last 10)
    var userWins: [MiningRound] = [];
    var winCount: Nat = 0;
    let totalRounds = miningRounds.size();
    
    if (totalRounds > 0) {
      var i: Int = Int.abs(totalRounds) - 1;
      while (i >= 0 and winCount < 10) {
        let round = miningRounds[Int.abs(i)];
        switch (round.winner) {
          case (?winner) {
            if (Principal.equal(winner, user)) {
              userWins := Array.append(userWins, [round]);
              winCount += 1;
            };
          };
          case null {};
        };
        i -= 1;
      };
    };
    
    // Get complete winning statistics from leaderboard
    let winningStats = switch (leaderboard.get(user)) {
      case (?entry) {
        {
          totalWins = entry.totalWins;
          totalRewards = entry.totalRewards;
          currentWinStreak = entry.winStreak;
          longestWinStreak = entry.longestWinStreak;
          lastWinRound = ?entry.lastWinRound;
        }
      };
      case null {
        {
          totalWins = 0;
          totalRewards = 0;
          currentWinStreak = 0;
          longestWinStreak = 0;
          lastWinRound = null;
        }
      };
    };

    // Calculate time to next block
    let now = Time.now();
    let nextBlockTime = lastBlockTime + BLOCK_DURATION_NS;
    let timeToNext = if (nextBlockTime > now) { nextBlockTime - now } else { 0 };
    
    {
      miners = userMinerList;
      stats = {
        totalMiners = minerIds.size();
        activeMiners = activeCount;
        totalDirtBalance = totalDirt;
        totalMiningPower = totalPower;
        totalDailyRate = totalRate;
      };
      recentWins = userWins;
      winningStats = winningStats;
      systemInfo = {
        currentRound = currentRound;
        timeToNextBlock = timeToNext;
        blockReward = BLOCK_REWARD;
      };
    }
  };
  
  public query func getAllActiveMiners(): async [Miner] {
    var activeList: [Miner] = [];
    for ((id, miner) in miners.entries()) {
      if (miner.isActive) {
        activeList := Array.append(activeList, [miner]);
      };
    };
    activeList
  };
  
  public query func getTotalActiveMiners(): async Nat {
    var count: Nat = 0;
    for ((id, miner) in miners.entries()) {
      if (miner.isActive) {
        count += 1;
      };
    };
    count
  };
  
  public query func getTotalMinersCreated(): async Nat {
    totalMinersCreated
  };
  
  public query func getCurrentRound(): async Nat {
    currentRound
  };
  
  public query func getLastBlockTime(): async Int {
    lastBlockTime
  };
  
  public query func getTimeToNextBlock(): async Int {
    let now = Time.now();
    let nextBlockTime = lastBlockTime + BLOCK_DURATION_NS;
    if (nextBlockTime > now) {
      nextBlockTime - now
    } else {
      0
    }
  };
  
  public query func getMiningRounds(start: Nat, count: Nat): async [MiningRound] {
    let totalRounds = miningRounds.size();
    if (start >= totalRounds) {
      return [];
    };
    let endIndex = Nat.min(start + count, totalRounds);
    // Use safe subtraction to prevent arithmetic traps
    let length = safeSub(endIndex, start);
    Array.subArray(miningRounds, start, length)
  };
  
  public query func getLatestMiningRounds(count: Nat): async [MiningRound] {
    let totalRounds = miningRounds.size();
    if (totalRounds == 0) {
      return [];
    };
    // Use safe subtraction to prevent arithmetic traps
    let startIndex = safeSub(totalRounds, count);
    let length = safeSub(totalRounds, startIndex);
    Array.subArray(miningRounds, startIndex, length)
  };

  public query func getDirtToken(): async Principal {
    dirtTokenCanister
  };
  
  public query func getAK69Token(): async Principal {
    ak69TokenCanister
  };

  public query func getOwner(): async Principal {
    owner
  };
  
  public query func getBlockReward(): async Nat {
    BLOCK_REWARD
  };
  
  public query func getBlockDuration(): async Nat {
    BLOCK_DURATION_SECONDS
  };
  
  public query func getMiningConfig(): async {minDailyRate: Nat; maxDailyRate: Nat; blockReward: Nat; blockDurationSeconds: Nat} {
    {
      minDailyRate = MIN_DAILY_DIRT_RATE;
      maxDailyRate = MAX_DAILY_DIRT_RATE;
      blockReward = BLOCK_REWARD;
      blockDurationSeconds = BLOCK_DURATION_SECONDS;
    }
  };
  
  public query func getBurnAddress(): async Principal {
    BURN_ADDRESS
  };

  // --- Leaderboard Query Functions ---

  // Get top winners leaderboard (most efficient for frontend)
  public query func getLeaderboard(limit: Nat): async [LeaderboardEntry] {
    let maxLimit = if (limit > 100) { 100 } else { limit }; // Cap at 100 for performance
    var entries: [LeaderboardEntry] = [];
    
    // Convert HashMap to array
    for ((user, entry) in leaderboard.entries()) {
      entries := Array.append(entries, [entry]);
    };
    
    // Sort by total wins (descending), then by total rewards (descending)
    let sortedEntries = Array.sort(entries, func(a: LeaderboardEntry, b: LeaderboardEntry) : Order.Order {
      if (a.totalWins > b.totalWins) { #less }
      else if (a.totalWins < b.totalWins) { #greater }
      else if (a.totalRewards > b.totalRewards) { #less }
      else if (a.totalRewards < b.totalRewards) { #greater }
      else { #equal }
    });
    
    // Return top entries
    let endIndex = Nat.min(maxLimit, sortedEntries.size());
    Array.subArray(sortedEntries, 0, endIndex)
  };

  // Get leaderboard by total rewards (alternative ranking)
  public query func getLeaderboardByRewards(limit: Nat): async [LeaderboardEntry] {
    let maxLimit = if (limit > 100) { 100 } else { limit };
    var entries: [LeaderboardEntry] = [];
    
    for ((user, entry) in leaderboard.entries()) {
      entries := Array.append(entries, [entry]);
    };
    
    let sortedEntries = Array.sort(entries, func(a: LeaderboardEntry, b: LeaderboardEntry) : Order.Order {
      if (a.totalRewards > b.totalRewards) { #less }
      else if (a.totalRewards < b.totalRewards) { #greater }
      else if (a.totalWins > b.totalWins) { #less }
      else if (a.totalWins < b.totalWins) { #greater }
      else { #equal }
    });
    
    let endIndex = Nat.min(maxLimit, sortedEntries.size());
    Array.subArray(sortedEntries, 0, endIndex)
  };

  // Get leaderboard by current win streak
  public query func getLeaderboardByStreak(limit: Nat): async [LeaderboardEntry] {
    let maxLimit = if (limit > 100) { 100 } else { limit };
    var entries: [LeaderboardEntry] = [];
    
    for ((user, entry) in leaderboard.entries()) {
      entries := Array.append(entries, [entry]);
    };
    
    let sortedEntries = Array.sort(entries, func(a: LeaderboardEntry, b: LeaderboardEntry) : Order.Order {
      if (a.winStreak > b.winStreak) { #less }
      else if (a.winStreak < b.winStreak) { #greater }
      else if (a.totalWins > b.totalWins) { #less }
      else if (a.totalWins < b.totalWins) { #greater }
      else { #equal }
    });
    
    let endIndex = Nat.min(maxLimit, sortedEntries.size());
    Array.subArray(sortedEntries, 0, endIndex)
  };

  // Get specific user's leaderboard entry
  public query func getUserLeaderboardEntry(user: Principal): async ?LeaderboardEntry {
    leaderboard.get(user)
  };

  // Get user's leaderboard rank (by total wins)
  public query func getUserRank(user: Principal): async ?Nat {
    switch (leaderboard.get(user)) {
      case (?userEntry) {
        var rank: Nat = 1;
        for ((otherUser, entry) in leaderboard.entries()) {
          if (entry.totalWins > userEntry.totalWins or 
              (entry.totalWins == userEntry.totalWins and entry.totalRewards > userEntry.totalRewards)) {
            rank += 1;
          };
        };
        ?rank
      };
      case null null;
    }
  };

  // Get comprehensive leaderboard statistics  
  public query func getLeaderboardStats(): async LeaderboardStats {
    // Directly get top 10 winners instead of calling another query function
    var entries: [LeaderboardEntry] = [];
    for ((user, entry) in leaderboard.entries()) {
      entries := Array.append(entries, [entry]);
    };
    
    let sortedEntries = Array.sort(entries, func(a: LeaderboardEntry, b: LeaderboardEntry) : Order.Order {
      if (a.totalWins > b.totalWins) { #less }
      else if (a.totalWins < b.totalWins) { #greater }
      else if (a.totalRewards > b.totalRewards) { #less }
      else if (a.totalRewards < b.totalRewards) { #greater }
      else { #equal }
    });
    
    let topWinners = Array.subArray(sortedEntries, 0, Nat.min(10, sortedEntries.size()));
    
    {
      topWinners = topWinners;
      totalUniqueWinners = leaderboard.size();
      totalRewardsPaid = totalRewardsPaidGlobal;
      lastUpdated = Time.now();
    }
  };

  // Get complete leaderboard dashboard (most efficient for frontend)
  public query func getLeaderboardDashboard(): async {
    topWinners: [LeaderboardEntry];
    topByRewards: [LeaderboardEntry];
    currentStreaks: [LeaderboardEntry];
    stats: LeaderboardStats;
    recentRounds: [MiningRound];
  } {
    // Get all entries once and sort multiple ways
    var entries: [LeaderboardEntry] = [];
    for ((user, entry) in leaderboard.entries()) {
      entries := Array.append(entries, [entry]);
    };
    
    // Sort by wins
    let sortedByWins = Array.sort(entries, func(a: LeaderboardEntry, b: LeaderboardEntry) : Order.Order {
      if (a.totalWins > b.totalWins) { #less }
      else if (a.totalWins < b.totalWins) { #greater }
      else if (a.totalRewards > b.totalRewards) { #less }
      else if (a.totalRewards < b.totalRewards) { #greater }
      else { #equal }
    });
    
    // Sort by rewards  
    let sortedByRewards = Array.sort(entries, func(a: LeaderboardEntry, b: LeaderboardEntry) : Order.Order {
      if (a.totalRewards > b.totalRewards) { #less }
      else if (a.totalRewards < b.totalRewards) { #greater }
      else if (a.totalWins > b.totalWins) { #less }
      else if (a.totalWins < b.totalWins) { #greater }
      else { #equal }
    });
    
    // Sort by current streak
    let sortedByStreak = Array.sort(entries, func(a: LeaderboardEntry, b: LeaderboardEntry) : Order.Order {
      if (a.winStreak > b.winStreak) { #less }
      else if (a.winStreak < b.winStreak) { #greater }
      else if (a.totalWins > b.totalWins) { #less }
      else if (a.totalWins < b.totalWins) { #greater }
      else { #equal }
    });
    
    // Get recent rounds
    let totalRounds = miningRounds.size();
    let recentRounds = if (totalRounds == 0) {
      []
    } else {
      let startIndex = if (totalRounds >= 5) { totalRounds - 5 } else { 0 };
      let length = totalRounds - startIndex;
      Array.subArray(miningRounds, startIndex, length)
    };
    
    // Create stats
    let stats: LeaderboardStats = {
      topWinners = Array.subArray(sortedByWins, 0, Nat.min(10, sortedByWins.size()));
      totalUniqueWinners = leaderboard.size();
      totalRewardsPaid = totalRewardsPaidGlobal;
      lastUpdated = Time.now();
    };
    
    {
      topWinners = Array.subArray(sortedByWins, 0, Nat.min(10, sortedByWins.size()));
      topByRewards = Array.subArray(sortedByRewards, 0, Nat.min(10, sortedByRewards.size()));
      currentStreaks = Array.subArray(sortedByStreak, 0, Nat.min(10, sortedByStreak.size()));
      stats = stats;
      recentRounds = recentRounds;
    }
  };

  // --- OPTIMIZED Leaderboard Query Functions (Cycle Efficient) ---

  // Ultra-fast leaderboard queries using cached data
  public query func getLeaderboardOptimized(limit: Nat): async [LeaderboardEntry] {
    let maxLimit = if (limit > 100) { 100 } else { limit };
    let endIndex = Nat.min(maxLimit, cachedByWins.size());
    Array.subArray(cachedByWins, 0, endIndex)
  };

  public query func getLeaderboardByRewardsOptimized(limit: Nat): async [LeaderboardEntry] {
    let maxLimit = if (limit > 100) { 100 } else { limit };
    let endIndex = Nat.min(maxLimit, cachedByRewards.size());
    Array.subArray(cachedByRewards, 0, endIndex)
  };

  public query func getLeaderboardByStreakOptimized(limit: Nat): async [LeaderboardEntry] {
    let maxLimit = if (limit > 100) { 100 } else { limit };
    let endIndex = Nat.min(maxLimit, cachedByStreak.size());
    Array.subArray(cachedByStreak, 0, endIndex)
  };

  // Optimized rank calculation using cached sorted data
  public query func getUserRankOptimized(user: Principal): async ?Nat {
    switch (leaderboard.get(user)) {
      case (?userEntry) {
        // Find user in cached sorted array (much faster than iteration)
        var rank: Nat = 1;
        for (entry in cachedByWins.vals()) {
          if (Principal.equal(entry.user, user)) {
            return ?rank;
          };
          rank += 1;
        };
        null // User not found in cache
      };
      case null null;
    }
  };

  // Ultra-efficient dashboard (uses all cached data)
  public query func getLeaderboardDashboardOptimized(): async {
    topWinners: [LeaderboardEntry];
    topByRewards: [LeaderboardEntry];
    currentStreaks: [LeaderboardEntry];
    totalUniqueWinners: Nat;
    totalRewardsPaid: Nat;
    cacheStatus: {entriesCount: Nat; isDirty: Bool; lastUpdated: Int;};
  } {
    {
      topWinners = Array.subArray(cachedByWins, 0, Nat.min(10, cachedByWins.size()));
      topByRewards = Array.subArray(cachedByRewards, 0, Nat.min(10, cachedByRewards.size()));
      currentStreaks = Array.subArray(cachedByStreak, 0, Nat.min(10, cachedByStreak.size()));
      totalUniqueWinners = leaderboard.size();
      totalRewardsPaid = totalRewardsPaidGlobal;
      cacheStatus = {
        entriesCount = cachedByWins.size();
        isDirty = cacheIsDirty;
        lastUpdated = lastCacheUpdate;
      };
    }
  };

  // Get cache status
  public query func getCacheStatus(): async {
    entriesCount: Nat;
    lastUpdated: Int;
    isDirty: Bool;
    secondsSinceUpdate: Int;
  } {
    let now = Time.now();
    let secondsSince = (now - lastCacheUpdate) / 1_000_000_000;
    
    {
      entriesCount = cachedByWins.size();
      lastUpdated = lastCacheUpdate;
      isDirty = cacheIsDirty;
      secondsSinceUpdate = Int.abs(secondsSince);
    }
  };

  // --- Admin Configuration Functions ---
  
  public shared (msg) func setConfiguration(newDirtToken: Principal, newAK69Token: Principal, newOwner: Principal): async Result.Result<(), Text> {
    if (msg.caller != owner) {
      return #err("Only current owner can update configuration");
    };
    
    dirtTokenCanister := newDirtToken;
    ak69TokenCanister := newAK69Token;
    owner := newOwner;
    
    Debug.print("Configuration updated - DIRT: " # Principal.toText(newDirtToken) # ", AK69: " # Principal.toText(newAK69Token) # ", Owner: " # Principal.toText(newOwner));
    #ok(())
  };

  // Configure SIWE provider (admin only)
  public shared (msg) func setSiweProvider(canister : Principal) : async Result.Result<(), Text> {
    if (msg.caller != owner) { return #err("Only current owner can update SIWE provider"); };
    siweProvider := ?canister;
    Debug.print("SIWE provider set to: " # Principal.toText(canister));
    #ok(())
  };
  
  public shared (msg) func setDirtToken(newDirtToken: Principal): async Result.Result<(), Text> {
    if (msg.caller != owner) {
      return #err("Only owner can update DIRT token");
    };
    
    dirtTokenCanister := newDirtToken;
    Debug.print("DIRT token updated to: " # Principal.toText(newDirtToken));
    #ok(())
  };
  
  public shared (msg) func setAK69Token(newAK69Token: Principal): async Result.Result<(), Text> {
    if (msg.caller != owner) {
      return #err("Only owner can update AK69 token");
    };
    
    ak69TokenCanister := newAK69Token;
    Debug.print("AK69 token updated to: " # Principal.toText(newAK69Token));
    #ok(())
  };
  
  public shared (msg) func setOwner(newOwner: Principal): async Result.Result<(), Text> {
    if (msg.caller != owner) {
      return #err("Only current owner can update owner");
    };
    
    owner := newOwner;
    Debug.print("Owner updated to: " # Principal.toText(newOwner));
    #ok(())
  };

  // Rebuild leaderboard from historical mining rounds (admin only)
  public shared (msg) func rebuildLeaderboard(): async Result.Result<Text, Text> {
    if (msg.caller != owner) {
      return #err("Only owner can rebuild leaderboard");
    };
    
    // Clear existing leaderboard
    leaderboard := HashMap.HashMap<Principal, LeaderboardEntry>(20, Principal.equal, Principal.hash);
    totalRewardsPaidGlobal := 0;
    
    var processedRounds: Nat = 0;
    var totalRewards: Nat = 0;
    
    // Process all historical rounds
    for (round in miningRounds.vals()) {
      switch (round.winner) {
        case (?winner) {
          updateLeaderboard(winner, round.rewardsPaid, round.roundId);
          totalRewards += round.rewardsPaid;
          processedRounds += 1;
        };
        case null {};
      };
    };
    
    // Force cache refresh after rebuild
    refreshLeaderboardCache();
    
    let result = "Leaderboard rebuilt from " # Nat.toText(processedRounds) # " rounds with " # Nat.toText(totalRewards) # " total rewards. Found " # Nat.toText(leaderboard.size()) # " unique winners.";
    Debug.print(result);
    #ok(result)
  };

  // Batched rebuild with cycle limits (safer for large datasets)
  public shared (msg) func rebuildLeaderboardBatched(batchSize: Nat, startRound: Nat): async Result.Result<Text, Text> {
    if (msg.caller != owner) {
      return #err("Only owner can rebuild leaderboard");
    };
    
    let maxBatchSize = if (batchSize > 100) { 100 } else { batchSize }; // Limit batch size
    let totalRounds = miningRounds.size();
    let endRound = Nat.min(startRound + maxBatchSize, totalRounds);
    
    var processedRounds: Nat = 0;
    var totalRewards: Nat = 0;
    
    // Process limited batch to prevent cycle exhaustion
    if (startRound < totalRounds) {
      let roundsToProcess = Array.subArray(miningRounds, startRound, endRound - startRound);
      
      for (round in roundsToProcess.vals()) {
        switch (round.winner) {
          case (?winner) {
            updateLeaderboard(winner, round.rewardsPaid, round.roundId);
            totalRewards += round.rewardsPaid;
            processedRounds += 1;
          };
          case null {};
        };
      };
    };
    
    // Force cache refresh after batch
    if (processedRounds > 0) {
      refreshLeaderboardCache();
    };
    
    let result = "Processed rounds " # Nat.toText(startRound) # " to " # Nat.toText(endRound) # 
                 " (" # Nat.toText(processedRounds) # " with winners). " #
                 "Total: " # Nat.toText(leaderboard.size()) # " unique winners.";
    
    Debug.print(result);
    #ok(result)
  };

  // Force cache refresh (admin only)
  public shared (msg) func refreshLeaderboardCacheAdmin(): async Result.Result<Text, Text> {
    if (msg.caller != owner) {
      return #err("Only owner can refresh cache");
    };
    
    refreshLeaderboardCache();
    #ok("Cache refreshed successfully")
  };

  // --- System Health & Monitoring ---
  
  public query func getSystemHealth(): async {
    cyclesBalance: Nat;
    totalMiners: Nat;
    activeMiners: Nat;
    totalRounds: Nat;
    lastBlockTime: Int;
    timeToNextBlock: Int;
    isHealthy: Bool;
  } {
    let now = Time.now();
    let nextBlockTime = lastBlockTime + BLOCK_DURATION_NS;
    let timeToNext = if (nextBlockTime > now) { nextBlockTime - now } else { 0 };
    
    var activeMinerCount: Nat = 0;
    for ((id, miner) in miners.entries()) {
      if (miner.isActive) {
        activeMinerCount += 1;
      };
    };
    
    let cyclesBalance = Cycles.balance();
    let isHealthy = cyclesBalance > MIN_CYCLES_REQUIRED and totalMinersCreated < MAX_TOTAL_MINERS;
    
    {
      cyclesBalance = cyclesBalance;
      totalMiners = totalMinersCreated;
      activeMiners = activeMinerCount;
      totalRounds = miningRounds.size();
      lastBlockTime = lastBlockTime;
      timeToNextBlock = timeToNext;
      isHealthy = isHealthy;
    }
  };

  
};