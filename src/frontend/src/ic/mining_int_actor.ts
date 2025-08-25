import { Actor, HttpAgent } from "@dfinity/agent";
import type { Identity } from "@dfinity/agent";
import { IDL } from "@dfinity/candid";

// Create a patched mining actor that fixes the int/nat mismatches
export function createMiningPatchedActor(canisterId: string, identity?: Identity) {
  const agent = new HttpAgent({ host: "https://icp-api.io", identity });

  const idlFactory = ({ IDL }: { IDL: any }) => {
    const Account = IDL.Record({
      'owner' : IDL.Principal,
      'subaccount' : IDL.Opt(IDL.Vec(IDL.Nat8)),
    });

    // Based on console errors: "type on the wire int, expect type nat" - so use Int
    const PatchedMiner = IDL.Record({
      'id' : IDL.Int, // This is int on wire
      'dirtBalance' : IDL.Int, // This is int on wire
      'owner' : IDL.Principal,
      'miningPower' : IDL.Int, // This is int on wire
      'name' : IDL.Text,
      'createdAt' : IDL.Int, // This is int on wire
      'isActive' : IDL.Bool,
      'dailyDirtRate' : IDL.Int, // This is int on wire
      'lastActiveBlock' : IDL.Int, // This is int on wire
    });

    // getUserStats works fine, so keep these as Nat
    const UserStats = IDL.Record({
      'totalDailyRate' : IDL.Nat,
      'totalMiners' : IDL.Nat,
      'totalDirtBalance' : IDL.Nat,
      'totalMiningPower' : IDL.Nat,
      'activeMiners' : IDL.Nat,
    });

    // System info calls fail with "type on the wire int, expect type nat" - so use Int
    const SystemInfoCalls = {
      'getCurrentRound' : IDL.Func([], [IDL.Int], ['query']),
      'getTimeToNextBlock' : IDL.Func([], [IDL.Int], ['query']),
      'getBlockReward' : IDL.Func([], [IDL.Int], ['query']),
    };

    const MinerCreationArgs = IDL.Record({
      'miningPower' : IDL.Nat,
      'name' : IDL.Text,
      'initialDirtAmount' : IDL.Nat,
      'dailyDirtRate' : IDL.Nat,
    });

    const Tokens = IDL.Nat;
    const TxIndex = IDL.Nat;
    const TransferFromError = IDL.Variant({
      'GenericError' : IDL.Record({
        'message' : IDL.Text,
        'error_code' : IDL.Nat,
      }),
      'TemporarilyUnavailable' : IDL.Null,
      'InsufficientAllowance' : IDL.Record({ 'allowance' : Tokens }),
      'BadBurn' : IDL.Record({ 'min_burn_amount' : Tokens }),
      'Duplicate' : IDL.Record({ 'duplicate_of' : TxIndex }),
      'BadFee' : IDL.Record({ 'expected_fee' : Tokens }),
      'CreatedInFuture' : IDL.Record({ 'ledger_time' : IDL.Nat64 }),
      'TooOld' : IDL.Null,
      'InsufficientFunds' : IDL.Record({ 'balance' : Tokens }),
    });

    const MinerError = IDL.Variant({
      'InvalidInput' : IDL.Text,
      'TransferError' : TransferFromError,
      'SystemError' : IDL.Text,
      'NotAuthorized' : IDL.Text,
      'MinerNotFound' : IDL.Text,
      'InvalidDirtRate' : IDL.Text,
      'InsufficientFunds' : IDL.Text,
    });

    const CreateMinerResult = IDL.Variant({ 'ok' : IDL.Nat, 'err' : MinerError });
    const EditMinerResult = IDL.Variant({ 'ok' : IDL.Bool, 'err' : MinerError });

    return IDL.Service({
      'getUserMinersDetailed' : IDL.Func([IDL.Principal], [IDL.Vec(PatchedMiner)], ['query']),
      'getUserStats' : IDL.Func([IDL.Principal], [UserStats], ['query']),
      'getCurrentRound' : SystemInfoCalls.getCurrentRound,
      'getTimeToNextBlock' : SystemInfoCalls.getTimeToNextBlock,
      'getBlockReward' : SystemInfoCalls.getBlockReward,
      'createMiner' : IDL.Func([MinerCreationArgs], [CreateMinerResult], []),
      'editMiner' : IDL.Func(
        [IDL.Nat, IDL.Opt(IDL.Text), IDL.Opt(IDL.Nat), IDL.Opt(IDL.Nat)],
        [EditMinerResult],
        [],
      ),
    });
  };

  return Actor.createActor(idlFactory as any, { agent, canisterId });
}
