// SPDX-License-Identifier: MIT
// AK69 ICRC-1 & ICRC-2 Compliant Fungible Token
// Version: 4.1.1 – 21 Jul 2025 (Fixed Compilation Issues)
//
// This is the definitive, self-contained canister with compilation fixes:
// 1. Corrected array type declaration for stable variables
// 2. Fixed time conversion functions
// 3. Replaced non-existent Array.some with Array.find
// 4. Added valid controller principal (replace with your actual principal)
// 5. Enhanced deduplication logic for better security

import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Time "mo:base/Time";
import Result "mo:base/Result";
import Iter "mo:base/Iter";
import Int "mo:base/Int";
import OrderedMap "mo:base/OrderedMap";
import Order "mo:base/Order";
import Buffer "mo:base/Buffer";

actor AK69Token {

  // ------------------------------
  // 1. Type Definitions
  // ------------------------------
  public type Subaccount = Blob;
  public type Account = { owner : Principal; subaccount : ?Subaccount };
  public type Tokens = Nat;
  public type Memo = Blob;
  public type Timestamp = Nat64;
  public type Duration = Nat64;
  public type TxIndex = Nat;

  public type DeduplicationError = {
    #TooOld;
    #Duplicate : { duplicate_of : TxIndex };
    #CreatedInFuture : { ledger_time : Timestamp };
  };
  public type CommonError = {
    #InsufficientFunds : { balance : Tokens };
    #BadFee : { expected_fee : Tokens };
    #TemporarilyUnavailable;
    #GenericError : { error_code : Nat; message : Text };
  };
  public type TransferError = DeduplicationError or CommonError or {
    #BadBurn : { min_burn_amount : Tokens };
  };
  public type ApproveError = DeduplicationError or CommonError or {
    #Expired : { ledger_time : Timestamp };
    #AllowanceChanged : { current_allowance : Tokens };
  };
  public type TransferFromError = TransferError or {
    #InsufficientAllowance : { allowance : Tokens };
  };

  public type Allowance = { allowance : Tokens; expires_at : ?Timestamp };
  public type TransferOp = {
    #Transfer : { from : Account; to : Account; amount : Tokens; spender : ?Account };
    #Mint : { to : Account; amount : Tokens };
    #Burn : { from : Account; amount : Tokens; spender : ?Account };
    #Approve : { from : Account; spender : Account; amount : Tokens; expires_at : ?Timestamp; expected_allowance: ?Tokens };
  };
  public type Transaction = {
    ts  : Timestamp;
    op  : TransferOp;
    fee : Tokens;
    memo: ?Memo;
  };

  // --------------------------
  // 2. Helper Functions (declared before use)
  // --------------------------

  func blob_cmp(a: Blob, b: Blob) : Order.Order {
    if (a < b) #less else if (a > b) #greater else #equal
  };

  func account_cmp(a : Account, b : Account) : Order.Order {
    let p_cmp = Principal.compare(a.owner, b.owner);
    switch p_cmp {
      case (#equal) {
        switch (a.subaccount, b.subaccount) {
          case (null, null) { #equal };
          case (null, ?_) { #less };
          case (?_, null) { #greater };
          case (?sa, ?sb) { blob_cmp(sa, sb) };
        }
      };
      case other { other };
    }
  };

  func allowance_key_cmp(a: (Account, Account), b: (Account, Account)) : Order.Order {
      let owner_cmp = account_cmp(a.0, b.0);
      switch owner_cmp {
        case (#equal) { account_cmp(a.1, b.1) };
        case other { other };
      }
  };

  // ------------------------------
  // 3. State
  // ------------------------------

  // --- Configuration ---
  stable var _name : Text = "AK69";
  stable var _symbol : Text = "AK69";
  stable var _decimals : Nat8 = 9;
  stable var _fee : Tokens = 10_000;
  // TODO: Replace with your actual controller principal ID(s)
  // Example: stable var _controllers : [Principal] = [Principal.fromText("hpikg-6exdt-jn33w-ndty3-fc7jc-tl2lr-buih3-cs3y7-tftkp-sfp62-gqe")];
  stable var _controllers : [Principal] = [Principal.fromText("hpikg-6exdt-jn33w-ndty3-fc7jc-tl2lr-buih3-cs3y7-tftkp-sfp62-gqe")]; // Default anonymous principal - CHANGE THIS!

  // --- Ledger State ---
  let accountOps = OrderedMap.Make<Account>(account_cmp);
  let allowanceOps = OrderedMap.Make<(Account, Account)>(allowance_key_cmp);
  let blobOps = OrderedMap.Make<Blob>(blob_cmp);

  stable var _balances = accountOps.empty<Tokens>();
  stable var _allowances = allowanceOps.empty<Allowance>();
  stable var _totalSupply : Tokens = 0;

  // --- Transaction Log & Deduplication ---
  stable let LOG_CAPACITY : Nat = 2000;
  stable var _transactions : [var ?Transaction] = Array.init(LOG_CAPACITY, null);
  stable var _tx_count : Nat = 0; // Total transactions ever recorded
  stable var _next_tx_idx : TxIndex = 0;

  let TX_WINDOW : Duration = 24 * 60 * 60 * 1_000_000_000;
  let PERMITTED_DRIFT : Duration = 2 * 60 * 1_000_000_000;
  stable var _dedup_log = blobOps.empty<TxIndex>();


  // --------------------------
  // 4. Internal Logic
  // --------------------------

  func _only_controller(caller: Principal) : Bool {
    switch (Array.find<Principal>(_controllers, func(c: Principal) : Bool { Principal.equal(c, caller) })) {
      case (?_) { true };
      case null { false };
    }
  };

  func _get_balance(acc : Account) : Tokens {
    Option.get(accountOps.get(_balances, acc), 0)
  };

  func _credit(acc : Account, amt : Tokens) {
    let bal = _get_balance(acc);
    _balances := accountOps.put(_balances, acc, bal + amt);
  };

  func _debit(acc : Account, amt : Tokens) : Result.Result<Tokens, TransferError> {
    let bal = _get_balance(acc);
    if (bal < amt) { return #err(#InsufficientFunds { balance = bal }) };
    _balances := accountOps.put(_balances, acc, bal - amt);
    #ok(bal - amt)
  };

  func _record(op : TransferOp, fee: Tokens, memo: ?Memo) : TxIndex {
    let idx = _next_tx_idx;
    let tx : Transaction = { ts = Nat64.fromNat(Int.abs(Time.now())); op = op; fee = fee; memo = memo };

    _transactions[idx % LOG_CAPACITY] := ?tx;
    _tx_count += 1;
    _next_tx_idx += 1;
    idx
  };

  func _check_deduplication(caller: Principal, ts: ?Timestamp, memo: ?Memo) : Result.Result<(), DeduplicationError> {
      let now_nanos = Nat64.fromNat(Int.abs(Time.now()));
      let created_at_time = Option.get(ts, now_nanos);

      // Safe subtraction with bounds checking
      let min_time = if (now_nanos > TX_WINDOW + PERMITTED_DRIFT) {
        now_nanos - TX_WINDOW - PERMITTED_DRIFT
      } else { 0 : Nat64 };

      if (created_at_time < min_time) {
          return #err(#TooOld);
      };
      if (created_at_time > now_nanos + PERMITTED_DRIFT) {
          return #err(#CreatedInFuture{ ledger_time = now_nanos });
      };

      // Enhanced deduplication hash with more entropy
      let buf = Buffer.Buffer<Nat8>(200);
      let callerBlob = Principal.toBlob(caller);
      let callerBytes = Blob.toArray(callerBlob);
      for (byte in callerBytes.vals()) {
        buf.add(byte);
      };
      
      // Add timestamp for more entropy
      let timeBytes = Blob.toArray(Blob.fromArray([
        Nat8.fromNat(Nat64.toNat(created_at_time) % 256),
        Nat8.fromNat((Nat64.toNat(created_at_time) / 256) % 256),
        Nat8.fromNat((Nat64.toNat(created_at_time) / 65536) % 256),
        Nat8.fromNat((Nat64.toNat(created_at_time) / 16777216) % 256)
      ]));
      for (byte in timeBytes.vals()) {
        buf.add(byte);
      };

      // Add memo if present
      switch (memo) {
        case (?m) {
          let memoBytes = Blob.toArray(m);
          for (byte in memoBytes.vals()) {
            buf.add(byte);
          };
        };
        case null { buf.add(0); };
      };

      let hasher = Blob.fromArray(Buffer.toArray(buf));

      switch (blobOps.get(_dedup_log, hasher)) {
          case (?existing_idx) { return #err(#Duplicate{ duplicate_of = existing_idx }); };
          case null {
              _dedup_log := blobOps.put(_dedup_log, hasher, _next_tx_idx);
              #ok(())
          };
      };
  };

  func _get_allowance(owner: Account, spender: Account) : Allowance {
    let allowance = Option.get(allowanceOps.get(_allowances, (owner, spender)), { allowance=0; expires_at=null });
    let now_nanos = Nat64.fromNat(Int.abs(Time.now()));
    switch (allowance.expires_at) {
        case (?expiry) {
            if (expiry < now_nanos) {
                return { allowance = 0; expires_at = allowance.expires_at };
            };
        };
        case null {};
    };
    allowance
  };

  // --------------------------
  // 5. Lifecycle & Initialization
  // --------------------------
  // Initialization logic runs directly in the actor body.
  let initial_supply : Tokens = 1_000_000_000_000_000_000;
  if (initial_supply > 0 and Array.size(_controllers) > 0) {
    let ownerAcc : Account = { owner = _controllers[0]; subaccount = null };
    _balances := accountOps.put(_balances, ownerAcc, initial_supply);
    _totalSupply := initial_supply;
    ignore _record(#Mint{ to=ownerAcc; amount=initial_supply }, 0, null);
  };

  // --------------------------
  // 6. Public API – ICRC-1
  // --------------------------
  public query func icrc1_name() : async Text { _name };
  public query func icrc1_symbol() : async Text { _symbol };
  public query func icrc1_decimals() : async Nat8 { _decimals };
  public query func icrc1_fee() : async Tokens { _fee };
  public query func icrc1_total_supply() : async Tokens { _totalSupply };
  public query func icrc1_balance_of(acc : Account) : async Tokens { _get_balance(acc) };
  public query func icrc1_supported_standards() : async [{ name : Text; url : Text }] {
    [ { name="ICRC-1"; url="https://github.com/dfinity/ICRC-1" },
      { name="ICRC-2"; url="https://github.com/dfinity/ICRC-1/tree/main/standards/ICRC-2" } ]
  };
  public query func icrc1_metadata() : async [(Text, { #Nat : Nat; #Text : Text; #Blob: Blob })] {
    [ ("icrc1:name", #Text(_name)),
      ("icrc1:symbol", #Text(_symbol)),
      ("icrc1:decimals", #Nat(Nat8.toNat(_decimals))),
      ("icrc1:fee", #Nat(_fee)) ]
  };

  public shared(msg) func icrc1_transfer(args : {
    from_subaccount : ?Subaccount;
    to : Account;
    amount : Tokens;
    fee : ?Tokens;
    memo : ?Memo;
    created_at_time : ?Timestamp;
  }) : async Result.Result<TxIndex, TransferError> {
    switch (_check_deduplication(msg.caller, args.created_at_time, args.memo)) {
      case (#err e) { return #err(e) };
      case (#ok _) {};
    };

    let from_acc : Account = { owner = msg.caller; subaccount = args.from_subaccount };
    let fee = Option.get(args.fee, _fee);
    if (fee != _fee) { return #err(#BadFee{ expected_fee = _fee }) };

    // Add zero-amount validation
    if (args.amount == 0) {
      return #err(#GenericError({ error_code = 100; message = "Transfer amount must be greater than zero" }));
    };

    // Prevent self-transfer (saves user fees)
    if (account_cmp(from_acc, args.to) == #equal) {
      return #err(#GenericError({ error_code = 101; message = "Cannot transfer to same account" }));
    };

    let total_debit = fee + args.amount;
    if (_get_balance(from_acc) < total_debit) {
      return #err(#InsufficientFunds{ balance = _get_balance(from_acc) })
    };

    switch (_debit(from_acc, total_debit)) {
      case (#err e) { return #err(e) };
      case (#ok _) {};
    };
    _credit(args.to, args.amount);

    let op = #Transfer({ from=from_acc; to=args.to; amount=args.amount; spender = null });
    let txid = _record(op, fee, args.memo);
    #ok(txid)
  };

  // --------------------------
  // 7. Public API – ICRC-2
  // --------------------------
  public shared(msg) func icrc2_approve(args : {
    from_subaccount : ?Subaccount;
    spender : Account;
    amount : Tokens;
    expected_allowance : ?Tokens;
    expires_at : ?Timestamp;
    fee : ?Tokens;
    memo : ?Memo;
    created_at_time : ?Timestamp;
  }) : async Result.Result<TxIndex, ApproveError> {
    switch (_check_deduplication(msg.caller, args.created_at_time, args.memo)) {
      case (#err e) { return #err(e) };
      case (#ok _) {};
    };

    let from_acc : Account = { owner = msg.caller; subaccount = args.from_subaccount };
    let fee = Option.get(args.fee, _fee);
    if (fee != _fee) { return #err(#BadFee{ expected_fee = _fee }) };

    let now_nanos = Nat64.fromNat(Int.abs(Time.now()));
    switch (args.expires_at) {
        case (?expiry) { if (expiry < now_nanos) { return #err(#Expired{ ledger_time = now_nanos }); }; };
        case null {};
    };

    switch (_debit(from_acc, fee)) {
      case (#err(#InsufficientFunds(r))) { return #err(#InsufficientFunds(r)) };
      case (#err(e)) { return #err(#GenericError({error_code = 1; message = "Unexpected debit error" }))};
      case (#ok _) {};
    };

    let allowance_key = (from_acc, args.spender);
    let current_allowance = _get_allowance(from_acc, args.spender);

    switch (args.expected_allowance) {
        case (?expected) {
            if (expected != current_allowance.allowance) {
                _credit(from_acc, fee); // Refund fee
                return #err(#AllowanceChanged{ current_allowance = current_allowance.allowance });
            };
        };
        case null {};
    };

    let new_allowance : Allowance = { allowance = args.amount; expires_at = args.expires_at };
    _allowances := allowanceOps.put(_allowances, allowance_key, new_allowance);

    let op = #Approve({ from = from_acc; spender = args.spender; amount = args.amount; expires_at = args.expires_at; expected_allowance = args.expected_allowance; });
    let txid = _record(op, fee, args.memo);
    #ok(txid)
  };

  public query func icrc2_allowance(args : { account : Account; spender : Account }) : async Allowance {
    _get_allowance(args.account, args.spender)
  };

  public shared(msg) func icrc2_transfer_from(args : {
    spender_subaccount : ?Subaccount;
    from : Account;
    to : Account;
    amount : Tokens;
    fee : ?Tokens;
    memo : ?Memo;
    created_at_time : ?Timestamp;
  }) : async Result.Result<TxIndex, TransferFromError> {
    let spender_acc : Account = { owner = msg.caller; subaccount = args.spender_subaccount };
    
    switch (_check_deduplication(msg.caller, args.created_at_time, args.memo)) {
      case (#err e) { return #err(e) };
      case (#ok _) {};
    };

    let fee = Option.get(args.fee, _fee);
    if (fee != _fee) { return #err(#BadFee{ expected_fee = _fee }) };

    // Add zero-amount validation
    if (args.amount == 0) {
      return #err(#GenericError({ error_code = 100; message = "Transfer amount must be greater than zero" }));
    };

    // Prevent self-transfer (optional - saves user fees)
    if (account_cmp(args.from, args.to) == #equal) {
      return #err(#GenericError({ error_code = 101; message = "Cannot transfer to same account" }));
    };

    let allowance = _get_allowance(args.from, spender_acc);

    let total_debit = args.amount + fee;
    if (allowance.allowance < total_debit) {
        return #err(#InsufficientAllowance{ allowance = allowance.allowance });
    };
    if (_get_balance(args.from) < total_debit) {
        return #err(#InsufficientFunds{ balance = _get_balance(args.from) });
    };

    // 🔒 SECURITY: Safe subtraction (already validated above)
    let new_allowance_val = allowance.allowance - total_debit;
    let new_allowance = { allowance = new_allowance_val; expires_at = allowance.expires_at };
    _allowances := allowanceOps.put(_allowances, (args.from, spender_acc), new_allowance);

    switch (_debit(args.from, total_debit)) {
        case (#err e) { return #err(e) }; // Should not happen
        case (#ok _) {};
    };
    _credit(args.to, args.amount);

    let op = #Transfer({ from=args.from; to=args.to; amount=args.amount; spender = ?spender_acc });
    let txid = _record(op, fee, args.memo);
    #ok(txid)
  };

  // --------------------------
  // 8. Admin & Maintenance
  // --------------------------
  public shared(msg) func admin_mint(to : Account, amount : Tokens) : async Result.Result<TxIndex, Text> {
    if (not _only_controller(msg.caller)) {
      return #err("Caller is not a designated controller.");
    };
    _credit(to, amount);
    _totalSupply += amount;
    #ok(_record(#Mint{ to=to; amount=amount }, 0, null))
  };

  public shared(msg) func admin_burn(from : Account, amount : Tokens) : async Result.Result<TxIndex, TransferError> {
    if (not _only_controller(msg.caller)) {
      return #err(#GenericError({ error_code = 999; message = "Caller is not a designated controller." }));
    };
    switch (_debit(from, amount)) {
      case (#ok(_)) {
        _totalSupply -= amount;
        let op = #Burn({ from=from; amount=amount; spender=null });
        #ok(_record(op, 0, null))
      };
      case (#err(e)) { #err(e) };
    }
  };

  public shared(msg) func admin_set_fee(new_fee : Tokens) : async Result.Result<(), Text> {
    if (not _only_controller(msg.caller)) {
      return #err("Caller is not a designated controller.");
    };
    _fee := new_fee;
    #ok(())
  };

  public shared(msg) func admin_set_controllers(new_controllers: [Principal]) : async Result.Result<(), Text> {
      if (not _only_controller(msg.caller)) {
        return #err("Caller is not a designated controller.");
      };
      if (Array.size(new_controllers) == 0) {
          return #err("Cannot remove all controllers.");
      };
      _controllers := new_controllers;
      #ok(())
  };

  public query func get_transactions(start: Nat, length: Nat) : async { transactions: [Transaction] } {
      var res : [Transaction] = [];
      let max_tx = Nat.min(start + length, _tx_count);
      if (start >= max_tx) {
        return { transactions = [] };
      };
      for (i in Iter.range(start, max_tx - 1)) {
        switch(_transactions[i % LOG_CAPACITY]) {
          case (?tx) { res := Array.append(res, [tx]); };
          case null {};
        }
      };
      { transactions = res }
  };
}
