import { Actor, HttpAgent } from "@dfinity/agent";
import type { Identity } from "@dfinity/agent";
import { IDL } from "@dfinity/candid";

// Create a robust mining actor that handles mixed int/nat types
export function createMiningRobustActor(canisterId: string, identity?: Identity) {
  const agent = new HttpAgent({ host: "https://icp-api.io", identity });

  const idlFactory = ({ IDL }: { IDL: any }) => {
    // Use a flexible number type that can be either int or nat
    const FlexibleInt = IDL.Variant({
      'int': IDL.Int,
      'nat': IDL.Nat,
    });

    // For records, we'll use Text for all numeric fields and parse them manually
    // This bypasses the strict type checking
    const FlexibleMiner = IDL.Record({
      'id' : IDL.Text, // Will be parsed as number
      'dirtBalance' : IDL.Text,
      'owner' : IDL.Principal,
      'miningPower' : IDL.Text,
      'name' : IDL.Text,
      'createdAt' : IDL.Text,
      'lifetimeWins' : IDL.Text,
      'isActive' : IDL.Bool,
      'dailyDirtRate' : IDL.Text,
      'lastActiveBlock' : IDL.Text,
    });

    const FlexibleWinningStats = IDL.Record({
      'totalRewards' : IDL.Text,
      'totalWins' : IDL.Text,
      'lastWinRound' : IDL.Opt(IDL.Text),
      'longestWinStreak' : IDL.Text,
      'currentWinStreak' : IDL.Text,
    });

    const FlexibleStats = IDL.Record({
      'totalDailyRate' : IDL.Text,
      'totalMiners' : IDL.Text,
      'totalDirtBalance' : IDL.Text,
      'totalMiningPower' : IDL.Text,
      'activeMiners' : IDL.Text,
    });

    const FlexibleSystemInfo = IDL.Record({
      'currentRound' : IDL.Text,
      'timeToNextBlock' : IDL.Text,
      'blockReward' : IDL.Text,
    });

    const FlexibleMiningRound = IDL.Record({
      'startTime' : IDL.Text,
      'isCompleted' : IDL.Bool,
      'endTime' : IDL.Text,
      'winner' : IDL.Opt(IDL.Principal),
      'totalDirtConsumed' : IDL.Text,
      'roundId' : IDL.Text,
      'winnerMiner' : IDL.Opt(IDL.Text),
      'randomSeed' : IDL.Opt(IDL.Vec(IDL.Nat8)),
      'totalActiveMiners' : IDL.Text,
      'rewardsPaid' : IDL.Text,
    });

    const UserDashboardResult = IDL.Record({
      'winningStats' : FlexibleWinningStats,
      'miners' : IDL.Vec(FlexibleMiner),
      'recentWins' : IDL.Vec(FlexibleMiningRound),
      'stats' : FlexibleStats,
      'systemInfo' : FlexibleSystemInfo,
    });

    return IDL.Service({
      'getUserDashboard' : IDL.Func([IDL.Principal], [UserDashboardResult], ['query']),
    });
  };

  return Actor.createActor(idlFactory as any, { agent, canisterId });
}

// Alternative approach: Use the raw call method to bypass Candid entirely
export async function getRawUserDashboard(canisterId: string, principal: any, identity?: Identity) {
  const agent = new HttpAgent({ host: "https://icp-api.io", identity });
  
  try {
    // Make a raw call to getUserDashboard
    const result = await agent.call(canisterId, {
      methodName: 'getUserDashboard',
      arg: IDL.encode([IDL.Principal], [principal]),
    });
    
    // Return the raw result - we'll parse it manually
    return result;
  } catch (error) {
    console.error('Raw call failed:', error);
    throw error;
  }
}
