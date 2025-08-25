import { Actor, HttpAgent } from "@dfinity/agent";
import type { Identity } from "@dfinity/agent";
import { IDL } from "@dfinity/candid";

export function createMiningTolerantActor(canisterId: string, identity?: Identity) {
  const agent = new HttpAgent({ host: "https://icp-api.io", identity });

  const idlFactory = ({ IDL }: { IDL: any }) => {
    const Subaccount = IDL.Vec(IDL.Nat8);
    const Account = IDL.Record({ owner: IDL.Principal, subaccount: IDL.Opt(Subaccount) });
    const Miner = IDL.Record({
      id: IDL.Int,
      dirtBalance: IDL.Int,
      owner: IDL.Principal,
      miningPower: IDL.Int,
      name: IDL.Text,
      createdAt: IDL.Int,
      lifetimeWins: IDL.Int,
      isActive: IDL.Bool,
      dailyDirtRate: IDL.Int,
      lastActiveBlock: IDL.Int,
    });

    const UserStats = IDL.Record({
      totalDailyRate: IDL.Int,
      totalMiners: IDL.Int,
      totalDirtBalance: IDL.Int,
      totalMiningPower: IDL.Int,
      activeMiners: IDL.Int,
    });

    return IDL.Service({
      getUserMinersDetailed: IDL.Func([IDL.Principal], [IDL.Vec(Miner)], ["query"]),
      getUserStats: IDL.Func([IDL.Principal], [UserStats], ["query"]),
      getCurrentRound: IDL.Func([], [IDL.Int], ["query"]),
      getTimeToNextBlock: IDL.Func([], [IDL.Int], ["query"]),
      getBlockReward: IDL.Func([], [IDL.Int], ["query"]),
    });
  };

  return Actor.createActor(idlFactory as any, { agent, canisterId });
}


