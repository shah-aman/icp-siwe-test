import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';
import type { IDL } from '@dfinity/candid';

export interface Account {
  'owner' : Principal,
  'subaccount' : [] | [Subaccount],
}
export interface LeaderboardEntry {
  'user' : Principal,
  'totalRewards' : bigint,
  'totalWins' : bigint,
  'lastWinRound' : bigint,
  'lastWinTime' : bigint,
  'longestWinStreak' : bigint,
  'winStreak' : bigint,
}
export interface LeaderboardStats {
  'totalRewardsPaid' : bigint,
  'lastUpdated' : bigint,
  'topWinners' : Array<LeaderboardEntry>,
  'totalUniqueWinners' : bigint,
}
export interface Miner {
  'id' : bigint,
  'dirtBalance' : bigint,
  'owner' : Principal,
  'miningPower' : bigint,
  'name' : string,
  'createdAt' : bigint,
  'isActive' : boolean,
  'dailyDirtRate' : bigint,
  'lastActiveBlock' : bigint,
}
export interface MinerCreationArgs {
  'miningPower' : bigint,
  'name' : string,
  'initialDirtAmount' : bigint,
  'dailyDirtRate' : bigint,
}
export type MinerError = { 'InvalidInput' : string } |
  { 'TransferError' : TransferFromError } |
  { 'SystemError' : string } |
  { 'NotAuthorized' : string } |
  { 'MinerNotFound' : string } |
  { 'InvalidDirtRate' : string } |
  { 'InsufficientFunds' : string };
export interface MiningRound {
  'startTime' : bigint,
  'isCompleted' : boolean,
  'endTime' : bigint,
  'winner' : [] | [Principal],
  'totalDirtConsumed' : bigint,
  'roundId' : bigint,
  'winnerMiner' : [] | [bigint],
  'randomSeed' : [] | [Uint8Array | number[]],
  'totalActiveMiners' : bigint,
  'rewardsPaid' : bigint,
}
export type Result = { 'ok' : boolean } |
  { 'err' : MinerError };
export type Result_1 = { 'ok' : null } |
  { 'err' : string };
export type Result_2 = { 'ok' : string } |
  { 'err' : string };
export type Result_3 = { 'ok' : Account } |
  { 'err' : string };
export type Result_4 = { 'ok' : bigint } |
  { 'err' : MinerError };
export type Subaccount = Uint8Array | number[];
export type Tokens = bigint;
export type TransferFromError = {
    'GenericError' : { 'message' : string, 'error_code' : bigint }
  } |
  { 'TemporarilyUnavailable' : null } |
  { 'InsufficientAllowance' : { 'allowance' : Tokens } } |
  { 'BadBurn' : { 'min_burn_amount' : Tokens } } |
  { 'Duplicate' : { 'duplicate_of' : TxIndex } } |
  { 'BadFee' : { 'expected_fee' : Tokens } } |
  { 'CreatedInFuture' : { 'ledger_time' : bigint } } |
  { 'TooOld' : null } |
  { 'InsufficientFunds' : { 'balance' : Tokens } };
export type TxIndex = bigint;
export interface _SERVICE {
  'catch_up' : ActorMethod<[], string>,
  'createMiner' : ActorMethod<[MinerCreationArgs], Result_4>,
  'createMinerFromDeposit' : ActorMethod<[MinerCreationArgs], Result_4>,
  'editMiner' : ActorMethod<
    [bigint, [] | [string], [] | [bigint], [] | [bigint]],
    Result
  >,
  'getAK69Token' : ActorMethod<[], Principal>,
  'getAllActiveMiners' : ActorMethod<[], Array<Miner>>,
  'getBlockDuration' : ActorMethod<[], bigint>,
  'getBlockReward' : ActorMethod<[], bigint>,
  'getBurnAddress' : ActorMethod<[], Principal>,
  'getCacheStatus' : ActorMethod<
    [],
    {
      'entriesCount' : bigint,
      'lastUpdated' : bigint,
      'isDirty' : boolean,
      'secondsSinceUpdate' : bigint,
    }
  >,
  'getCurrentRound' : ActorMethod<[], bigint>,
  'getDepositAccount' : ActorMethod<[], Result_3>,
  'getDirtToken' : ActorMethod<[], Principal>,
  'getLastBlockTime' : ActorMethod<[], bigint>,
  'getLatestMiningRounds' : ActorMethod<[bigint], Array<MiningRound>>,
  'getLeaderboard' : ActorMethod<[bigint], Array<LeaderboardEntry>>,
  'getLeaderboardByRewards' : ActorMethod<[bigint], Array<LeaderboardEntry>>,
  'getLeaderboardByRewardsOptimized' : ActorMethod<
    [bigint],
    Array<LeaderboardEntry>
  >,
  'getLeaderboardByStreak' : ActorMethod<[bigint], Array<LeaderboardEntry>>,
  'getLeaderboardByStreakOptimized' : ActorMethod<
    [bigint],
    Array<LeaderboardEntry>
  >,
  'getLeaderboardDashboard' : ActorMethod<
    [],
    {
      'currentStreaks' : Array<LeaderboardEntry>,
      'recentRounds' : Array<MiningRound>,
      'topWinners' : Array<LeaderboardEntry>,
      'stats' : LeaderboardStats,
      'topByRewards' : Array<LeaderboardEntry>,
    }
  >,
  'getLeaderboardDashboardOptimized' : ActorMethod<
    [],
    {
      'currentStreaks' : Array<LeaderboardEntry>,
      'totalRewardsPaid' : bigint,
      'cacheStatus' : {
        'entriesCount' : bigint,
        'lastUpdated' : bigint,
        'isDirty' : boolean,
      },
      'topWinners' : Array<LeaderboardEntry>,
      'topByRewards' : Array<LeaderboardEntry>,
      'totalUniqueWinners' : bigint,
    }
  >,
  'getLeaderboardOptimized' : ActorMethod<[bigint], Array<LeaderboardEntry>>,
  'getLeaderboardStats' : ActorMethod<[], LeaderboardStats>,
  'getMiner' : ActorMethod<[bigint], [] | [Miner]>,
  'getMinerLifetimeWins' : ActorMethod<[bigint], bigint>,
  'getMiningConfig' : ActorMethod<
    [],
    {
      'blockDurationSeconds' : bigint,
      'minDailyRate' : bigint,
      'blockReward' : bigint,
      'maxDailyRate' : bigint,
    }
  >,
  'getMiningRounds' : ActorMethod<[bigint, bigint], Array<MiningRound>>,
  'getOwner' : ActorMethod<[], Principal>,
  'getSystemHealth' : ActorMethod<
    [],
    {
      'totalMiners' : bigint,
      'lastBlockTime' : bigint,
      'isHealthy' : boolean,
      'totalRounds' : bigint,
      'timeToNextBlock' : bigint,
      'activeMiners' : bigint,
      'cyclesBalance' : bigint,
    }
  >,
  'getTimeToNextBlock' : ActorMethod<[], bigint>,
  'getTotalActiveMiners' : ActorMethod<[], bigint>,
  'getTotalMinersCreated' : ActorMethod<[], bigint>,
  'getUserDashboard' : ActorMethod<
    [Principal],
    {
      'winningStats' : {
        'totalRewards' : bigint,
        'totalWins' : bigint,
        'lastWinRound' : [] | [bigint],
        'longestWinStreak' : bigint,
        'currentWinStreak' : bigint,
      },
      'miners' : Array<
        {
          'id' : bigint,
          'dirtBalance' : bigint,
          'owner' : Principal,
          'miningPower' : bigint,
          'name' : string,
          'createdAt' : bigint,
          'lifetimeWins' : bigint,
          'isActive' : boolean,
          'dailyDirtRate' : bigint,
          'lastActiveBlock' : bigint,
        }
      >,
      'recentWins' : Array<MiningRound>,
      'stats' : {
        'totalDailyRate' : bigint,
        'totalMiners' : bigint,
        'totalDirtBalance' : bigint,
        'totalMiningPower' : bigint,
        'activeMiners' : bigint,
      },
      'systemInfo' : {
        'currentRound' : bigint,
        'timeToNextBlock' : bigint,
        'blockReward' : bigint,
      },
    }
  >,
  'getUserLeaderboardEntry' : ActorMethod<[Principal], [] | [LeaderboardEntry]>,
  'getUserMiners' : ActorMethod<[Principal], Array<bigint>>,
  'getUserMinersDetailed' : ActorMethod<[Principal], Array<Miner>>,
  'getUserMiningWins' : ActorMethod<[Principal, bigint], Array<MiningRound>>,
  'getUserRank' : ActorMethod<[Principal], [] | [bigint]>,
  'getUserRankOptimized' : ActorMethod<[Principal], [] | [bigint]>,
  'getUserStats' : ActorMethod<
    [Principal],
    {
      'totalDailyRate' : bigint,
      'totalMiners' : bigint,
      'totalDirtBalance' : bigint,
      'totalMiningPower' : bigint,
      'activeMiners' : bigint,
    }
  >,
  'mineBlock' : ActorMethod<[], string>,
  'pauseMiner' : ActorMethod<[bigint], Result>,
  'rebuildLeaderboard' : ActorMethod<[], Result_2>,
  'rebuildLeaderboardBatched' : ActorMethod<[bigint, bigint], Result_2>,
  'refreshLeaderboardCacheAdmin' : ActorMethod<[], Result_2>,
  'resumeMiner' : ActorMethod<[bigint], Result>,
  'setAK69Token' : ActorMethod<[Principal], Result_1>,
  'setConfiguration' : ActorMethod<[Principal, Principal, Principal], Result_1>,
  'setDirtToken' : ActorMethod<[Principal], Result_1>,
  'setOwner' : ActorMethod<[Principal], Result_1>,
  'setSiweProvider' : ActorMethod<[Principal], Result_1>,
  'siwe_lookup' : ActorMethod<
    [Principal],
    {
      'err' : [] | [string],
      'eth' : [] | [string],
      'stablePrincipal' : [] | [Principal],
      'input' : Principal,
      'siweProvider' : [] | [Principal],
    }
  >,
  'siwe_whoami' : ActorMethod<
    [],
    {
      'err' : [] | [string],
      'stablePrincipal' : [] | [Principal],
      'caller' : Principal,
      'siweProvider' : [] | [Principal],
    }
  >,
  'topUpMiner' : ActorMethod<[bigint, bigint], Result>,
  'topUpMinerFromDeposit' : ActorMethod<[bigint, bigint], Result>,
}
export declare const idlFactory: IDL.InterfaceFactory;
export declare const init: (args: { IDL: typeof IDL }) => IDL.Type[];
