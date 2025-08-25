import { Actor, HttpAgent } from "@dfinity/agent";
import type { Identity } from "@dfinity/agent";
import { IDL } from "@dfinity/candid";

// Create a systematic mining actor based exactly on mining.did.d.ts
export function createMiningSystematicActor(canisterId: string, identity?: Identity) {
  const agent = new HttpAgent({ host: "https://icp-api.io", identity });

  const idlFactory = ({ IDL }: { IDL: any }) => {
    const Subaccount = IDL.Vec(IDL.Nat8);
    const Account = IDL.Record({
      'owner' : IDL.Principal,
      'subaccount' : IDL.Opt(Subaccount),
    });

    // Create a union type that can handle both Int and Nat
    const FlexibleNumber = IDL.Variant({
      'int': IDL.Int,
      'nat': IDL.Nat,
    });

    // For the miner, let's try using the actual types but with fallbacks
    const FlexibleMiner = IDL.Record({
      'id' : IDL.Nat, // Try Nat first since most seem to be Nat on wire
      'dirtBalance' : IDL.Nat,
      'owner' : IDL.Principal,
      'miningPower' : IDL.Nat,
      'name' : IDL.Text,
      'createdAt' : IDL.Nat,
      'lifetimeWins' : IDL.Nat,
      'isActive' : IDL.Bool,
      'dailyDirtRate' : IDL.Nat,
      'lastActiveBlock' : IDL.Nat,
    });

    const FlexibleMiningRound = IDL.Record({
      'startTime' : IDL.Nat,
      'isCompleted' : IDL.Bool,
      'endTime' : IDL.Nat,
      'winner' : IDL.Opt(IDL.Principal),
      'totalDirtConsumed' : IDL.Nat,
      'roundId' : IDL.Nat,
      'winnerMiner' : IDL.Opt(IDL.Nat),
      'randomSeed' : IDL.Opt(IDL.Vec(IDL.Nat8)),
      'totalActiveMiners' : IDL.Nat,
      'rewardsPaid' : IDL.Nat,
    });

    const FlexibleWinningStats = IDL.Record({
      'totalRewards' : IDL.Nat,
      'totalWins' : IDL.Nat,
      'lastWinRound' : IDL.Opt(IDL.Nat),
      'longestWinStreak' : IDL.Nat,
      'currentWinStreak' : IDL.Nat,
    });

    const FlexibleStats = IDL.Record({
      'totalDailyRate' : IDL.Nat,
      'totalMiners' : IDL.Nat,
      'totalDirtBalance' : IDL.Nat,
      'totalMiningPower' : IDL.Nat,
      'activeMiners' : IDL.Nat,
    });

    const FlexibleSystemInfo = IDL.Record({
      'currentRound' : IDL.Nat,
      'timeToNextBlock' : IDL.Nat,
      'blockReward' : IDL.Nat,
    });

    const UserDashboardResult = IDL.Record({
      'winningStats' : FlexibleWinningStats,
      'miners' : IDL.Vec(FlexibleMiner),
      'recentWins' : IDL.Vec(FlexibleMiningRound),
      'stats' : FlexibleStats,
      'systemInfo' : FlexibleSystemInfo,
    });

    const MinerCreationArgs = IDL.Record({
      'miningPower' : IDL.Nat,
      'name' : IDL.Text,
      'initialDirtAmount' : IDL.Nat,
      'dailyDirtRate' : IDL.Nat,
    });

    const MinerError = IDL.Variant({
      'InvalidInput' : IDL.Text,
      'TransferError' : IDL.Reserved,
      'SystemError' : IDL.Text,
      'NotAuthorized' : IDL.Text,
      'MinerNotFound' : IDL.Text,
      'InvalidDirtRate' : IDL.Text,
      'InsufficientFunds' : IDL.Text,
    });

    const CreateMinerResult = IDL.Variant({ 
      'ok' : IDL.Nat, 
      'err' : MinerError,
      'Ok' : IDL.Nat, 
      'Err' : MinerError 
    });

    const EditMinerResult = IDL.Variant({ 
      'ok' : IDL.Bool, 
      'err' : MinerError,
      'Ok' : IDL.Bool, 
      'Err' : MinerError 
    });

    return IDL.Service({
      'getUserDashboard' : IDL.Func([IDL.Principal], [UserDashboardResult], ['query']),
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
