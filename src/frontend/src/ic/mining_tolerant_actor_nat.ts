import { Actor, HttpAgent } from "@dfinity/agent";
import type { Identity } from "@dfinity/agent";
import { IDL } from "@dfinity/candid";

export function createMiningTolerantActorNat(canisterId: string, identity?: Identity) {
  const agent = new HttpAgent({ host: "https://icp-api.io", identity });

  const idlFactory = ({ IDL }: { IDL: any }) => {
    const Subaccount = IDL.Vec(IDL.Nat8);
    const Miner = IDL.Record({
      id: IDL.Nat,
      dirtBalance: IDL.Nat,
      owner: IDL.Principal,
      miningPower: IDL.Nat,
      name: IDL.Text,
      createdAt: IDL.Nat,
      lifetimeWins: IDL.Nat,
      isActive: IDL.Bool,
      dailyDirtRate: IDL.Nat,
      lastActiveBlock: IDL.Nat,
    });

    const UserStats = IDL.Record({
      totalDailyRate: IDL.Nat,
      totalMiners: IDL.Nat,
      totalDirtBalance: IDL.Nat,
      totalMiningPower: IDL.Nat,
      activeMiners: IDL.Nat,
    });

    return IDL.Service({
      getUserMinersDetailed: IDL.Func([IDL.Principal], [IDL.Vec(Miner)], ["query"]),
      getUserStats: IDL.Func([IDL.Principal], [UserStats], ["query"]),
      getCurrentRound: IDL.Func([], [IDL.Nat], ["query"]),
      getTimeToNextBlock: IDL.Func([], [IDL.Nat], ["query"]),
      getBlockReward: IDL.Func([], [IDL.Nat], ["query"]),
    });
  };

  return Actor.createActor(idlFactory as any, { agent, canisterId });
}


