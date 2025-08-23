import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Cycles "mo:base/ExperimentalCycles";
import Error "mo:base/Error";
import Float "mo:base/Float";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Int "mo:base/Int";

actor BridgeCanister {

  // ===============================
  // DRIFT Token Interface (ICRC-1/ICRC-2)
  // ===============================
  type Account = { owner : Principal; subaccount : ?Blob };
  type Tokens = Nat;
  type TxIndex = Nat;

  // ===============================
  // SIWE Provider (ic_siwe_provider) Interface
  // ===============================
  type GetAddressResponse = { #Ok : Text; #Err : Text };
  type GetPrincipalResponse = { #Ok : Blob; #Err : Text };

  type SiweProvider = actor {
    get_address : (Blob) -> async GetAddressResponse;
    get_principal : (Text) -> async GetPrincipalResponse;
  };

  type DriftTokenInterface = actor {
    admin_mint : shared (to : Account, amount : Tokens) -> async Result.Result<TxIndex, Text>;
    icrc1_balance_of : shared (account : Account) -> async Tokens;
    icrc1_total_supply : shared () -> async Tokens;
  };

  // ===============================
  // Burn Proof & Bridge Data Types
  // ===============================

  public type BurnProof = {
    // Base chain transaction details
    base_tx_hash : Text; // Transaction hash on base chain
    base_block_number : Nat64; // Block number on base chain
    base_chain_id : Nat64; // Chain ID (8453 for Base)

    // Burn event details
    token_address : Text; // Contract address of burned token
    token_symbol : Text; // Symbol of burned token (REGEN, GIV, KLIMA, etc.)
    burn_amount : Nat; // Amount burned (in token's native decimals)
    burn_amount_usd : Float; // USD value at burn time (decimal format, e.g., 1.50 for $1.50)

    // User details
    burner_address : Text; // EVM address that performed burn
    icp_recipient : Principal; // ICP principal to receive DRIFT tokens

    // Verification
    validator_signatures : [Blob]; // Multi-sig validator signatures
    verified : Bool; // Whether burn proof is verified
    processed : Bool; // Whether DRIFT tokens have been minted

    // Timestamps
    burn_timestamp : Nat64; // When burn occurred on base chain
    proof_timestamp : Nat64; // When proof was submitted to bridge
    process_timestamp : ?Nat64; // When DRIFT tokens were minted
  };

  public type BridgeTransaction = {
    id : Text; // Unique transaction ID
    burn_proof : BurnProof; // The burn proof
    drift_tx_hash : ?Text; // ICP transaction hash (after minting)
    drift_amount_minted : Nat; // Amount of DRIFT tokens minted
    status : BridgeStatus;
  };

  public type BridgeStatus = {
    #Pending; // Burn proof submitted, awaiting verification
    #Verified; // Burn proof verified, awaiting processing
    #Processed; // DRIFT tokens minted successfully
    #Failed : Text; // Processing failed with error message
    #Rejected : Text; // Burn proof rejected
  };

  public type ValidationResult = {
    #Valid;
    #Invalid : Text;
  };

  // ===============================
  // State Variables
  // ===============================

  private stable var owner : Principal = Principal.fromText("migqc-xlprm-vjeqv-4n6wp-mjz4m-npt42-hljcd-wczjg-ko6ud-dstyj-oqe");
  private stable var driftTokenCanister : ?Principal = null;
  private stable var siweProvider : ?Principal = null;

  // Validator system for multi-sig verification
  private stable var validators : [Principal] = []; // Validators managed separately from owner
  private stable var requiredSignatures : Nat = 0; // No signatures required until validators are added

  // Conversion rates
  private stable var usdToDriftRate : Nat = 100_000_000_000; // 1 USD = 100B DRIFT (9 decimals)

  // Storage for burn proofs and bridge transactions
  private let burnProofs = HashMap.HashMap<Text, BurnProof>(0, Text.equal, Text.hash);
  private stable var burnProofsEntries : [(Text, BurnProof)] = [];

  private let bridgeTransactions = HashMap.HashMap<Text, BridgeTransaction>(0, Text.equal, Text.hash);
  private stable var bridgeTransactionsEntries : [(Text, BridgeTransaction)] = [];

  // Nonce tracking to prevent replay attacks
  private let processedNonces = HashMap.HashMap<Text, Bool>(0, Text.equal, Text.hash);
  private stable var processedNoncesEntries : [(Text, Bool)] = [];

  // Supported tokens on base chain (populated by owner after deployment)
  private stable var supportedTokens : [(Text, Text)] = [];

  private stable var _minimumCycles : Nat = 1_000_000_000_000;

  // ===============================
  // Upgrade Functions
  // ===============================

  system func preupgrade() {
    burnProofsEntries := Iter.toArray(burnProofs.entries());
    bridgeTransactionsEntries := Iter.toArray(bridgeTransactions.entries());
    processedNoncesEntries := Iter.toArray(processedNonces.entries());
  };

  system func postupgrade() {
    for ((key, proof) in burnProofsEntries.vals()) {
      burnProofs.put(key, proof);
    };
    burnProofsEntries := [];

    for ((key, tx) in bridgeTransactionsEntries.vals()) {
      bridgeTransactions.put(key, tx);
    };
    bridgeTransactionsEntries := [];

    for ((key, value) in processedNoncesEntries.vals()) {
      processedNonces.put(key, value);
    };
    processedNoncesEntries := [];
  };

  // ===============================
  // Access Control
  // ===============================

  private func isOwner(caller : Principal) : Bool {
    Principal.equal(owner, caller);
  };
  // ===============================
  // SIWE Helpers
  // ===============================
  private func getStablePrincipalFromEth(eth : Text) : async Result.Result<Principal, Text> {
    switch (siweProvider) {
      case null { return #err("SIWE provider not configured"); };
      case (?prov) {
        let siwe : SiweProvider = actor (Principal.toText(prov));
        let resp = await siwe.get_principal(eth);
        switch (resp) {
          case (#Ok(blob)) { #ok(Principal.fromBlob(blob)) };
          case (#Err(e)) { #err(e) };
        }
      };
    }
  };


  private func isValidator(caller : Principal) : Bool {
    Array.find<Principal>(validators, func(p) { Principal.equal(p, caller) }) != null;
  };

  // ===============================
  // Utility Functions
  // ===============================

  private func generateTransactionId(burnProof : BurnProof) : Text {
    burnProof.base_tx_hash # "-" # Principal.toText(burnProof.icp_recipient) # "-" # Nat64.toText(burnProof.burn_timestamp);
  };

  private func calculateDriftAmount(burnAmountUsd : Float) : Nat {
    // burnAmountUsd is in decimal format (so $1.50 = 1.50)
    // Already validated to be > 0.0, so no need for Float.abs()
    // usdToDriftRate is 1_000_000_000 (1B, representing 1 USD = 1B DRIFT tokens)
    // To get the correct DRIFT amount in raw token units (9 decimals):
    // burnAmountUsd * usdToDriftRate * 1e9
    // For example: 1.50 * 1_000_000_000 * 1_000_000_000 = 1.5e18
    let driftFloat = burnAmountUsd * Float.fromInt(usdToDriftRate) * 1_000_000_000.0;
    Int.abs(Float.toInt(driftFloat));
  };

  private func validateBurnProof(proof : BurnProof) : ValidationResult {
    // Basic validation checks
    if (proof.base_tx_hash == "") {
      return #Invalid("Missing base transaction hash");
    };

    if (proof.burn_amount == 0) {
      return #Invalid("Burn amount must be greater than zero");
    };

    if (proof.burn_amount_usd <= 0.0) {
      return #Invalid("USD value must be greater than zero");
    };

    // Check if token is supported
    let isSupported = Array.find<(Text, Text)>(
      supportedTokens,
      func((addr, symbol)) {
        addr == proof.token_address;
      },
    ) != null;

    if (not isSupported) {
      return #Invalid("Token not supported for bridging");
    };

    // Check signature count
    if (proof.validator_signatures.size() < requiredSignatures) {
      return #Invalid("Insufficient validator signatures");
    };

    #Valid;
  };

  // ===============================
  // Main Bridge Functions
  // ===============================

  // Submit burn proof from base chain
  public shared (msg) func submitBurnProof(proof : BurnProof) : async Result.Result<Text, Text> {
    if (not (isValidator(msg.caller) or isOwner(msg.caller))) {
      return #err("Only validators or owner can submit burn proofs");
    };

    // Validate the burn proof
    switch (validateBurnProof(proof)) {
      case (#Invalid(reason)) {
        return #err("Invalid burn proof: " # reason);
      };
      case (#Valid) {};
    };

    let txId = generateTransactionId(proof);

    // Check for replay attacks
    switch (processedNonces.get(proof.base_tx_hash)) {
      case (?_) {
        return #err("Transaction already processed");
      };
      case null {};
    };

    // Store the burn proof
    let updatedProof = {
      proof with
      proof_timestamp = Nat64.fromNat(Int.abs(Time.now()));
      verified = true; // Mark as verified since validator submitted it
    };

    burnProofs.put(txId, updatedProof);

    // Create bridge transaction
    let bridgeTx : BridgeTransaction = {
      id = txId;
      burn_proof = updatedProof;
      drift_tx_hash = null;
      drift_amount_minted = calculateDriftAmount(proof.burn_amount_usd);
      status = #Verified;
    };

    bridgeTransactions.put(txId, bridgeTx);

    return #ok(txId);
  };

  // Process verified burn proof and mint DRIFT tokens
  public shared (msg) func processBurnProof(txId : Text) : async Result.Result<Text, Text> {
    if (not (isValidator(msg.caller) or isOwner(msg.caller))) {
      return #err("Only validators or owner can process burn proofs");
    };

    switch (driftTokenCanister) {
      case null {
        return #err("DRIFT token canister not configured");
      };
      case (?driftCanister) {
        switch (bridgeTransactions.get(txId)) {
          case null {
            return #err("Transaction not found");
          };
          case (?bridgeTx) {
            // Check if already processed
            switch (bridgeTx.status) {
              case (#Processed) {
                return #ok("Already processed");
              };
              case (#Failed(reason)) {
                return #err("Transaction previously failed: " # reason);
              };
              case (#Rejected(reason)) {
                return #err("Transaction rejected: " # reason);
              };
              case (#Pending or #Verified) {
                // Proceed with processing
              };
            };

            // Mark nonce as processed to prevent replay
            processedNonces.put(bridgeTx.burn_proof.base_tx_hash, true);

            // Decide mint recipient: prefer SIWE stable principal derived from burner_address
            let mintOwner : Principal = switch (await getStablePrincipalFromEth(bridgeTx.burn_proof.burner_address)) {
              case (#ok(p)) p;
              case (#err(_)) bridgeTx.burn_proof.icp_recipient; // fallback to provided ICP recipient
            };

            // Mint DRIFT tokens
            let driftToken : DriftTokenInterface = actor (Principal.toText(driftCanister));
            let recipient : Account = { owner = mintOwner; subaccount = null };

            try {
              let mintResult = await driftToken.admin_mint(recipient, bridgeTx.drift_amount_minted);

              switch (mintResult) {
                case (#ok(driftTxIndex)) {
                  // Update bridge transaction status
                  let updatedTx = {
                    bridgeTx with
                    drift_tx_hash = ?("drift_tx_" # Nat.toText(driftTxIndex));
                    status = #Processed;
                  };

                  let updatedProof = {
                    bridgeTx.burn_proof with
                    processed = true;
                    process_timestamp = ?Nat64.fromNat(Int.abs(Time.now()));
                  };

                  bridgeTransactions.put(txId, updatedTx);
                  burnProofs.put(txId, updatedProof);

                  return #ok("DRIFT tokens minted successfully. TX: " # Nat.toText(driftTxIndex));
                };
                case (#err(reason)) {
                  let failedTx = {
                    bridgeTx with
                    status = #Failed(reason);
                  };
                  bridgeTransactions.put(txId, failedTx);
                  return #err("Failed to mint DRIFT tokens: " # reason);
                };
              };
            } catch (error) {
              let failedTx = {
                bridgeTx with
                status = #Failed("Mint call failed: " # Error.message(error));
              };
              bridgeTransactions.put(txId, failedTx);
              return #err("Error calling DRIFT token: " # Error.message(error));
            };
          };
        };
      };
    };
  };

  // ===============================
  // Query Functions
  // ===============================

  public query func getBurnProof(txId : Text) : async ?BurnProof {
    burnProofs.get(txId);
  };

  public query func getBridgeTransaction(txId : Text) : async ?BridgeTransaction {
    bridgeTransactions.get(txId);
  };

  public query func getBridgeTransactionsByUser(user : Principal) : async [BridgeTransaction] {
    let userTxs = Buffer.Buffer<BridgeTransaction>(0);

    for ((_, tx) in bridgeTransactions.entries()) {
      if (Principal.equal(tx.burn_proof.icp_recipient, user)) {
        userTxs.add(tx);
      };
    };

    Buffer.toArray(userTxs);
  };

  public query func getPendingTransactions() : async [BridgeTransaction] {
    let pendingTxs = Buffer.Buffer<BridgeTransaction>(0);

    for ((_, tx) in bridgeTransactions.entries()) {
      switch (tx.status) {
        case (#Pending or #Verified) {
          pendingTxs.add(tx);
        };
        case _ {};
      };
    };

    Buffer.toArray(pendingTxs);
  };

  public query func getSupportedTokens() : async [(Text, Text)] {
    supportedTokens;
  };

  public query func getConversionRate() : async Nat {
    usdToDriftRate;
  };

  public query func getBridgeCanisterPrincipal() : async Principal {
    Principal.fromActor(BridgeCanister);
  };

  // ===============================
  // Admin Functions
  // ===============================

  public shared (msg) func setDriftTokenCanister(canister : Principal) : async Result.Result<(), Text> {
    if (not isOwner(msg.caller)) {
      return #err("Only owner can set DRIFT token canister");
    };

    driftTokenCanister := ?canister;
    #ok();
  };

  public shared (msg) func setSiweProvider(canister : Principal) : async Result.Result<(), Text> {
    if (not isOwner(msg.caller)) { return #err("Only owner can set SIWE provider"); };
    siweProvider := ?canister;
    #ok();
  };

  public shared (msg) func setValidators(newValidators : [Principal]) : async Result.Result<(), Text> {
    if (not isOwner(msg.caller)) {
      return #err("Only owner can set validators");
    };

    // Replace existing validators with new ones (no auto-inclusion of owner)
    validators := newValidators;
    #ok();
  };

  public shared (msg) func addValidator(validator : Principal) : async Result.Result<(), Text> {
    if (not isOwner(msg.caller)) {
      return #err("Only owner can add validators");
    };

    // Check if validator already exists
    let alreadyExists = Array.find<Principal>(validators, func(p) { Principal.equal(p, validator) }) != null;

    if (alreadyExists) {
      return #err("Validator already exists");
    };

    // Add new validator (append to existing list)
    validators := Array.append(validators, [validator]);
    #ok();
  };

  public query func getValidators() : async [Principal] {
    validators;
  };

  public query func getCurrentSettings() : async {
    owner : Principal;
    validators : [Principal];
    requiredSignatures : Nat;
    conversionRate : Nat;
  } {
    {
      owner = owner;
      validators = validators;
      requiredSignatures = requiredSignatures;
      conversionRate = usdToDriftRate;
    };
  };

  public shared (msg) func setRequiredSignatures(count : Nat) : async Result.Result<(), Text> {
    if (not isOwner(msg.caller)) {
      return #err("Only owner can set required signatures");
    };

    if (count > validators.size()) {
      return #err("Required signatures cannot exceed validator count");
    };

    requiredSignatures := count;
    #ok();
  };

  public shared (msg) func addSupportedToken(address : Text, symbol : Text) : async Result.Result<(), Text> {
    if (not isOwner(msg.caller)) {
      return #err("Only owner can add supported tokens");
    };

    supportedTokens := Array.append(supportedTokens, [(address, symbol)]);
    #ok();
  };

  public shared (msg) func setConversionRate(newRate : Nat) : async Result.Result<(), Text> {
    if (not isOwner(msg.caller)) {
      return #err("Only owner can set conversion rate");
    };

    usdToDriftRate := newRate;
    #ok();
  };

  public shared (msg) func rejectBurnProof(txId : Text, reason : Text) : async Result.Result<(), Text> {
    if (not (isValidator(msg.caller) or isOwner(msg.caller))) {
      return #err("Only validators or owner can reject burn proofs");
    };

    switch (bridgeTransactions.get(txId)) {
      case null {
        return #err("Transaction not found");
      };
      case (?tx) {
        let rejectedTx = {
          tx with
          status = #Rejected(reason);
        };
        bridgeTransactions.put(txId, rejectedTx);
        #ok();
      };
    };
  };

  // ===============================
  // System Functions
  // ===============================

  public func acceptCycles() : async () {
    let available = Cycles.available();
    let _accepted = Cycles.accept<system>(available);
  };

  public query func getCycleBalance() : async Nat {
    Cycles.balance();
  };

  public shared (msg) func resetCanister() : async Result.Result<(), Text> {
    if (not isOwner(msg.caller)) {
      return #err("Only owner can reset canister");
    };

    // Clear all data
    validators := [];
    requiredSignatures := 0;
    supportedTokens := [];

    let burnKeys = Buffer.Buffer<Text>(0);
    for ((key, _) in burnProofs.entries()) {
      burnKeys.add(key);
    };
    for (key in burnKeys.vals()) {
      ignore burnProofs.remove(key);
    };

    let bridgeKeys = Buffer.Buffer<Text>(0);
    for ((key, _) in bridgeTransactions.entries()) {
      bridgeKeys.add(key);
    };
    for (key in bridgeKeys.vals()) {
      ignore bridgeTransactions.remove(key);
    };

    let nonceKeys = Buffer.Buffer<Text>(0);
    for ((key, _) in processedNonces.entries()) {
      nonceKeys.add(key);
    };
    for (key in nonceKeys.vals()) {
      ignore processedNonces.remove(key);
    };

    // Reset stable variables
    burnProofsEntries := [];
    bridgeTransactionsEntries := [];
    processedNoncesEntries := [];

    #ok();
  };
};
