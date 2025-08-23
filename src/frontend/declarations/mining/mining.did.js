export const idlFactory = ({ IDL }) => {
  const Account = IDL.Record({
    'owner' : IDL.Principal,
    'subaccount' : IDL.Opt(IDL.Vec(IDL.Nat8)),
  });
  const LeaderboardEntry = IDL.Record({
    'user' : IDL.Principal,
    'totalRewards' : IDL.Nat,
    'totalWins' : IDL.Nat,
    'lastWinRound' : IDL.Nat,
    'lastWinTime' : IDL.Nat,
    'longestWinStreak' : IDL.Nat,
    'winStreak' : IDL.Nat,
  });
  const LeaderboardStats = IDL.Record({
    'totalRewardsPaid' : IDL.Nat,
    'lastUpdated' : IDL.Nat,
    'topWinners' : IDL.Vec(LeaderboardEntry),
    'totalUniqueWinners' : IDL.Nat,
  });
  const Miner = IDL.Record({
    'id' : IDL.Nat,
    'dirtBalance' : IDL.Nat,
    'owner' : IDL.Principal,
    'miningPower' : IDL.Nat,
    'name' : IDL.Text,
    'createdAt' : IDL.Nat,
    'isActive' : IDL.Bool,
    'dailyDirtRate' : IDL.Nat,
    'lastActiveBlock' : IDL.Nat,
  });
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
  const Result_4 = IDL.Variant({ 'ok' : IDL.Nat, 'err' : MinerError });
  const Result = IDL.Variant({ 'ok' : IDL.Bool, 'err' : MinerError });
  const MiningRound = IDL.Record({
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
  const Result_3 = IDL.Variant({ 'ok' : Account, 'err' : IDL.Text });
  const Result_2 = IDL.Variant({ 'ok' : IDL.Text, 'err' : IDL.Text });
  const Result_1 = IDL.Variant({ 'ok' : IDL.Null, 'err' : IDL.Text });
  return IDL.Service({
    'catch_up' : IDL.Func([], [IDL.Text], []),
    'createMiner' : IDL.Func([MinerCreationArgs], [Result_4], []),
    'createMinerFromDeposit' : IDL.Func([MinerCreationArgs], [Result_4], []),
    'editMiner' : IDL.Func(
        [IDL.Nat, IDL.Opt(IDL.Text), IDL.Opt(IDL.Nat), IDL.Opt(IDL.Nat)],
        [Result],
        [],
      ),
    'getAK69Token' : IDL.Func([], [IDL.Principal], ['query']),
    'getAllActiveMiners' : IDL.Func([], [IDL.Vec(Miner)], ['query']),
    'getBlockDuration' : IDL.Func([], [IDL.Nat], ['query']),
    'getBlockReward' : IDL.Func([], [IDL.Nat], ['query']),
    'getBurnAddress' : IDL.Func([], [IDL.Principal], ['query']),
    'getCacheStatus' : IDL.Func(
        [],
        [
          IDL.Record({
            'entriesCount' : IDL.Nat,
            'lastUpdated' : IDL.Nat,
            'isDirty' : IDL.Bool,
            'secondsSinceUpdate' : IDL.Nat,
          }),
        ],
        ['query'],
      ),
    'getCurrentRound' : IDL.Func([], [IDL.Nat], ['query']),
    'getDepositAccount' : IDL.Func([], [Result_3], ['query']),
    'getDirtToken' : IDL.Func([], [IDL.Principal], ['query']),
    'getLastBlockTime' : IDL.Func([], [IDL.Nat], ['query']),
    'getLatestMiningRounds' : IDL.Func([IDL.Nat], [IDL.Vec(MiningRound)], ['query']),
    'getLeaderboard' : IDL.Func([IDL.Nat], [IDL.Vec(LeaderboardEntry)], ['query']),
    'getLeaderboardByRewards' : IDL.Func(
        [IDL.Nat],
        [IDL.Vec(LeaderboardEntry)],
        ['query'],
      ),
    'getLeaderboardByRewardsOptimized' : IDL.Func(
        [IDL.Nat],
        [IDL.Vec(LeaderboardEntry)],
        ['query'],
      ),
    'getLeaderboardByStreak' : IDL.Func(
        [IDL.Nat],
        [IDL.Vec(LeaderboardEntry)],
        ['query'],
      ),
    'getLeaderboardByStreakOptimized' : IDL.Func(
        [IDL.Nat],
        [IDL.Vec(LeaderboardEntry)],
        ['query'],
      ),
    'getLeaderboardDashboard' : IDL.Func(
        [],
        [
          IDL.Record({
            'currentStreaks' : IDL.Vec(LeaderboardEntry),
            'recentRounds' : IDL.Vec(MiningRound),
            'topWinners' : IDL.Vec(LeaderboardEntry),
            'stats' : LeaderboardStats,
            'topByRewards' : IDL.Vec(LeaderboardEntry),
          }),
        ],
        ['query'],
      ),
    'getLeaderboardDashboardOptimized' : IDL.Func(
        [],
        [
          IDL.Record({
            'currentStreaks' : IDL.Vec(LeaderboardEntry),
            'totalRewardsPaid' : IDL.Nat,
            'cacheStatus' : IDL.Record({
              'entriesCount' : IDL.Nat,
              'lastUpdated' : IDL.Nat,
              'isDirty' : IDL.Bool,
            }),
            'topWinners' : IDL.Vec(LeaderboardEntry),
            'topByRewards' : IDL.Vec(LeaderboardEntry),
            'totalUniqueWinners' : IDL.Nat,
          }),
        ],
        ['query'],
      ),
    'getLeaderboardOptimized' : IDL.Func(
        [IDL.Nat],
        [IDL.Vec(LeaderboardEntry)],
        ['query'],
      ),
    'getLeaderboardStats' : IDL.Func([], [LeaderboardStats], ['query']),
    'getMiner' : IDL.Func([IDL.Nat], [IDL.Opt(Miner)], ['query']),
    'getMinerLifetimeWins' : IDL.Func([IDL.Nat], [IDL.Nat], ['query']),
    'getMiningConfig' : IDL.Func(
        [],
        [
          IDL.Record({
            'blockDurationSeconds' : IDL.Nat,
            'minDailyRate' : IDL.Nat,
            'blockReward' : IDL.Nat,
            'maxDailyRate' : IDL.Nat,
          }),
        ],
        ['query'],
      ),
    'getMiningRounds' : IDL.Func(
        [IDL.Nat, IDL.Nat],
        [IDL.Vec(MiningRound)],
        ['query'],
      ),
    'getOwner' : IDL.Func([], [IDL.Principal], ['query']),
    'getSystemHealth' : IDL.Func(
        [],
        [
          IDL.Record({
            'totalMiners' : IDL.Nat,
            'lastBlockTime' : IDL.Nat,
            'isHealthy' : IDL.Bool,
            'totalRounds' : IDL.Nat,
            'timeToNextBlock' : IDL.Nat,
            'activeMiners' : IDL.Nat,
            'cyclesBalance' : IDL.Nat,
          }),
        ],
        ['query'],
      ),
    'getTimeToNextBlock' : IDL.Func([], [IDL.Nat], ['query']),
    'getTotalActiveMiners' : IDL.Func([], [IDL.Nat], ['query']),
    'getTotalMinersCreated' : IDL.Func([], [IDL.Nat], ['query']),
    'getUserDashboard' : IDL.Func(
        [IDL.Principal],
        [
          IDL.Record({
            'winningStats' : IDL.Record({
              'totalRewards' : IDL.Nat,
              'totalWins' : IDL.Nat,
              'lastWinRound' : IDL.Opt(IDL.Nat),
              'longestWinStreak' : IDL.Nat,
              'currentWinStreak' : IDL.Nat,
            }),
            'miners' : IDL.Vec(
              IDL.Record({
                'id' : IDL.Nat,
                'dirtBalance' : IDL.Nat,
                'owner' : IDL.Principal,
                'miningPower' : IDL.Nat,
                'name' : IDL.Text,
                'createdAt' : IDL.Nat,
                'lifetimeWins' : IDL.Nat,
                'isActive' : IDL.Bool,
                'dailyDirtRate' : IDL.Nat,
                'lastActiveBlock' : IDL.Nat,
              })
            ),
            'recentWins' : IDL.Vec(MiningRound),
            'stats' : IDL.Record({
              'totalDailyRate' : IDL.Nat,
              'totalMiners' : IDL.Nat,
              'totalDirtBalance' : IDL.Nat,
              'totalMiningPower' : IDL.Nat,
              'activeMiners' : IDL.Nat,
            }),
            'systemInfo' : IDL.Record({
              'currentRound' : IDL.Nat,
              'timeToNextBlock' : IDL.Nat,
              'blockReward' : IDL.Nat,
            }),
          }),
        ],
        ['query'],
      ),
    'getUserLeaderboardEntry' : IDL.Func(
        [IDL.Principal],
        [IDL.Opt(LeaderboardEntry)],
        ['query'],
      ),
    'getUserMiners' : IDL.Func([IDL.Principal], [IDL.Vec(IDL.Nat)], ['query']),
    'getUserMinersDetailed' : IDL.Func(
        [IDL.Principal],
        [IDL.Vec(Miner)],
        ['query'],
      ),
    'getUserMiningWins' : IDL.Func(
        [IDL.Principal, IDL.Nat],
        [IDL.Vec(MiningRound)],
        ['query'],
      ),
    'getUserRank' : IDL.Func([IDL.Principal], [IDL.Opt(IDL.Nat)], ['query']),
    'getUserRankOptimized' : IDL.Func(
        [IDL.Principal],
        [IDL.Opt(IDL.Nat)],
        ['query'],
      ),
    'getUserStats' : IDL.Func(
        [IDL.Principal],
        [
          IDL.Record({
            'totalDailyRate' : IDL.Nat,
            'totalMiners' : IDL.Nat,
            'totalDirtBalance' : IDL.Nat,
            'totalMiningPower' : IDL.Nat,
            'activeMiners' : IDL.Nat,
          }),
        ],
        ['query'],
      ),
    'mineBlock' : IDL.Func([], [IDL.Text], []),
    'pauseMiner' : IDL.Func([IDL.Nat], [Result], []),
    'rebuildLeaderboard' : IDL.Func([], [Result_2], []),
    'rebuildLeaderboardBatched' : IDL.Func([IDL.Nat, IDL.Nat], [Result_2], []),
    'refreshLeaderboardCacheAdmin' : IDL.Func([], [Result_2], []),
    'resumeMiner' : IDL.Func([IDL.Nat], [Result], []),
    'setAK69Token' : IDL.Func([IDL.Principal], [Result_1], []),
    'setConfiguration' : IDL.Func(
        [IDL.Principal, IDL.Principal, IDL.Principal],
        [Result_1],
        [],
      ),
    'setDirtToken' : IDL.Func([IDL.Principal], [Result_1], []),
    'setOwner' : IDL.Func([IDL.Principal], [Result_1], []),
    'setSiweProvider' : IDL.Func([IDL.Principal], [Result_1], []),
    'siwe_lookup' : IDL.Func(
        [IDL.Principal],
        [
          IDL.Record({
            'err' : IDL.Opt(IDL.Text),
            'eth' : IDL.Opt(IDL.Text),
            'stablePrincipal' : IDL.Opt(IDL.Principal),
            'input' : IDL.Principal,
            'siweProvider' : IDL.Opt(IDL.Principal),
          }),
        ],
        ['query'],
      ),
    'siwe_whoami' : IDL.Func(
        [],
        [
          IDL.Record({
            'err' : IDL.Opt(IDL.Text),
            'stablePrincipal' : IDL.Opt(IDL.Principal),
            'caller' : IDL.Principal,
            'siweProvider' : IDL.Opt(IDL.Principal),
          }),
        ],
        ['query'],
      ),
    'topUpMiner' : IDL.Func([IDL.Nat, IDL.Nat], [Result], []),
    'topUpMinerFromDeposit' : IDL.Func([IDL.Nat, IDL.Nat], [Result], []),
  });
};
export const init = ({ IDL }) => { return []; };
