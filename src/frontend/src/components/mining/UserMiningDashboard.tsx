import { useEffect, useMemo, useState } from "react";
import { useMiningActor } from "../../ic/actor_providers";
import { useStablePrincipal } from "../../hooks/useStablePrincipal";
import { Principal } from "@dfinity/principal";
import toast from "react-hot-toast";
import canisterIds from "../../ic/canister_ids.json";
import { createMiningPatchedActor } from "../../ic/mining_patched_actor";

type DashboardMiner = {
  id: bigint;
  dirtBalance: bigint;
  owner: Principal;
  miningPower: bigint;
  name: string;
  createdAt: bigint;
  lifetimeWins: bigint;
  isActive: boolean;
  dailyDirtRate: bigint;
  lastActiveBlock: bigint;
};

type WinningStats = {
  totalRewards: bigint;
  totalWins: bigint;
  lastWinRound: [] | [bigint];
  longestWinStreak: bigint;
  currentWinStreak: bigint;
};

type DashboardStats = {
  totalDailyRate: bigint;
  totalMiners: bigint;
  totalDirtBalance: bigint;
  totalMiningPower: bigint;
  activeMiners: bigint;
};

type SystemInfo = {
  currentRound: bigint;
  timeToNextBlock: bigint;
  blockReward: bigint;
};

type UserDashboardResponse = {
  winningStats: WinningStats;
  miners: DashboardMiner[];
  recentWins: any[];
  stats: DashboardStats;
  systemInfo: SystemInfo;
};

function formatBigInt(n: bigint, decimals = 0): string {
  if (decimals <= 0) return n.toString();
  const s = n.toString().padStart(decimals + 1, "0");
  const i = s.length - decimals;
  return `${s.slice(0, i)}.${s.slice(i)}`.replace(/^0+(?=\d)/, "");
}

export default function UserMiningDashboard() {
  const { actor: miningActor } = useMiningActor();
  const { stablePrincipal, loading: stableLoading, error: stableError } = useStablePrincipal();

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dashboard, setDashboard] = useState<UserDashboardResponse | null>(null);

  const canQuery = useMemo(() => !!miningActor && !!stablePrincipal, [miningActor, stablePrincipal]);

  const fetchDashboard = async () => {
    if (!miningActor || !stablePrincipal) return;
    setLoading(true);
    setError(null);
    try {
      // Skip the problematic getUserDashboard and call individual methods
      // Use the original miningActor which works for individual calls
      
      console.log("Fetching dashboard data using individual calls...");
      
      // Helper function to safely convert to BigInt
      const safeBigInt = (value: any): bigint => {
        if (value === null || value === undefined) return 0n;
        if (typeof value === 'bigint') return value;
        if (typeof value === 'number') return BigInt(value);
        if (typeof value === 'string' && value !== '') return BigInt(value);
        return 0n;
      };

      // Fetch data using individual method calls that work
      let miners: DashboardMiner[] = [];
      let stats: any = {};
      let currentRound: bigint = 0n;
      let timeToNextBlock: bigint = 0n;
      let blockReward: bigint = 0n;

      try {
        // Try with original mining actor first to see raw data
        console.log("Trying getUserMinersDetailed with original actor...");
        const minersResult = await miningActor.getUserMinersDetailed(stablePrincipal);
        console.log("Raw miners result (original actor):", minersResult);
        
        miners = (minersResult || []).map((miner: any) => ({
          id: safeBigInt(miner.id),
          dirtBalance: safeBigInt(miner.dirtBalance),
          owner: miner.owner,
          miningPower: safeBigInt(miner.miningPower),
          name: miner.name || "",
          createdAt: safeBigInt(miner.createdAt),
          lifetimeWins: 0n, // Not available in getUserMinersDetailed
          isActive: Boolean(miner.isActive),
          dailyDirtRate: safeBigInt(miner.dailyDirtRate),
          lastActiveBlock: safeBigInt(miner.lastActiveBlock),
        }));
      } catch (e) {
        console.error("Error fetching miners (original actor):", e);
        
        // If original fails, try with patched actor
        try {
          console.log("Trying getUserMinersDetailed with patched actor...");
          const miningCanisterId = canisterIds.mining["mainnet"];
          const patchedActor: any = createMiningPatchedActor(miningCanisterId);
          const minersResult2 = await patchedActor.getUserMinersDetailed(stablePrincipal);
          console.log("Raw miners result (patched actor):", minersResult2);
          
          miners = (minersResult2 || []).map((miner: any) => ({
            id: safeBigInt(miner.id),
            dirtBalance: safeBigInt(miner.dirtBalance),
            owner: miner.owner,
            miningPower: safeBigInt(miner.miningPower),
            name: miner.name || "",
            createdAt: safeBigInt(miner.createdAt),
            lifetimeWins: 0n,
            isActive: Boolean(miner.isActive),
            dailyDirtRate: safeBigInt(miner.dailyDirtRate),
            lastActiveBlock: safeBigInt(miner.lastActiveBlock),
          }));
        } catch (e2) {
          console.error("Error fetching miners (patched actor):", e2);
        }
      }

      try {
        // Get user stats using original actor (this works)
        const statsResult = await miningActor.getUserStats(stablePrincipal);
        console.log("Raw stats result:", statsResult);
        stats = statsResult || {};
      } catch (e) {
        console.error("Error fetching stats:", e);
      }

      try {
        // Get system info using original actor
        console.log("Trying system info with original actor...");
        currentRound = safeBigInt(await miningActor.getCurrentRound());
        timeToNextBlock = safeBigInt(await miningActor.getTimeToNextBlock());
        blockReward = safeBigInt(await miningActor.getBlockReward());
      } catch (e) {
        console.error("Error fetching system info (original actor):", e);
      }

      const dashboard: UserDashboardResponse = {
        winningStats: {
          totalRewards: 0n, // Not available via individual calls
          totalWins: 0n,
          lastWinRound: [],
          longestWinStreak: 0n,
          currentWinStreak: 0n,
        },
        miners,
        recentWins: [], // Not available via individual calls
        stats: {
          totalDailyRate: safeBigInt(stats.totalDailyRate),
          totalMiners: safeBigInt(stats.totalMiners),
          totalDirtBalance: safeBigInt(stats.totalDirtBalance),
          totalMiningPower: safeBigInt(stats.totalMiningPower),
          activeMiners: safeBigInt(stats.activeMiners),
        },
        systemInfo: {
          currentRound,
          timeToNextBlock,
          blockReward,
        },
      };

      console.log("Final dashboard:", dashboard);
      setDashboard(dashboard);
    } catch (e: any) {
      console.error("Dashboard fetch error", e);
      setError(e.message ?? "Failed to fetch dashboard");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (canQuery) {
      fetchDashboard();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canQuery]);

  const [editing, setEditing] = useState<Record<string, boolean>>({});
  const [editName, setEditName] = useState<Record<string, string>>({});
  const [editMiningPower, setEditMiningPower] = useState<Record<string, string>>({});
  const [editDailyRate, setEditDailyRate] = useState<Record<string, string>>({});
  const [isSaving, setIsSaving] = useState<Record<string, boolean>>({});

  const toggleEdit = (id: bigint, current: DashboardMiner) => {
    const key = id.toString();
    setEditing((p) => ({ ...p, [key]: !p[key] }));
    // Prefill inputs once
    setEditName((p) => ({ ...p, [key]: p[key] ?? current.name }));
    setEditMiningPower((p) => ({ ...p, [key]: p[key] ?? current.miningPower.toString() }));
    setEditDailyRate((p) => ({ ...p, [key]: p[key] ?? current.dailyDirtRate.toString() }));
  };

  const updateMiner = async (id: bigint) => {
    const key = id.toString();
    const name = (editName[key] ?? "").trim();
    const miningPowerStr = (editMiningPower[key] ?? "").trim();
    const dailyRateStr = (editDailyRate[key] ?? "").trim();

    let nameOpt: [] | [string] = [];
    let powerOpt: [] | [bigint] = [];
    let rateOpt: [] | [bigint] = [];

    if (name.length > 0) nameOpt = [name];
    if (miningPowerStr.length > 0 && !isNaN(Number(miningPowerStr))) powerOpt = [BigInt(miningPowerStr)];
    if (dailyRateStr.length > 0 && !isNaN(Number(dailyRateStr))) rateOpt = [BigInt(dailyRateStr)];

    setIsSaving((p) => ({ ...p, [key]: true }));
    const toastId = toast.loading("Updating miner...");
    try {
      // Use patched actor for editMiner
      const miningCanisterId = canisterIds.mining["mainnet"];
      const patchedActor: any = createMiningPatchedActor(miningCanisterId);
      
      const result = await patchedActor.editMiner(id, nameOpt, powerOpt, rateOpt);
      if ("ok" in result || "Ok" in result) {
        toast.success("Miner updated", { id: toastId });
        // Refresh dashboard
        fetchDashboard();
        setEditing((p) => ({ ...p, [key]: false }));
      } else {
        const err = (result as any).err || (result as any).Err;
        toast.error(`Update failed: ${JSON.stringify(err)}`, { id: toastId });
      }
    } catch (e: any) {
      toast.error(e.message ?? "Update failed", { id: toastId });
    } finally {
      setIsSaving((p) => ({ ...p, [key]: false }));
    }
  };

  if (stableLoading) {
    return null;
  }

  return (
    <div className="w-full max-w-2xl p-6 space-y-4 font-mono border-2 rounded-lg bg-zinc-900 border-zinc-700">
      <h2 className="text-xl font-bold text-center text-cyan-400">Your Mining Dashboard</h2>

      <div className="flex items-center justify-between">
        <button
          onClick={fetchDashboard}
          disabled={!canQuery || loading}
          className="px-3 py-1 text-sm font-bold text-white bg-blue-600 rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {loading ? "Refreshing..." : "Refresh"}
        </button>
        {stablePrincipal && (
          <div className="text-xs text-zinc-400">User: {stablePrincipal.toText()}</div>
        )}
      </div>

      {stableError && <p className="text-red-400">{stableError}</p>}
      {error && <p className="text-red-400">{error}</p>}

      {dashboard && (
        <>
          <div className="grid grid-cols-1 gap-3 p-4 rounded-md bg-zinc-800">
            <div className="flex justify-between"><span className="text-zinc-400">Total Miners</span><span className="font-bold">{dashboard.stats.totalMiners.toString()}</span></div>
            <div className="flex justify-between"><span className="text-zinc-400">Active Miners</span><span className="font-bold">{dashboard.stats.activeMiners.toString()}</span></div>
            <div className="flex justify-between"><span className="text-zinc-400">Total Daily Rate</span><span className="font-bold">{dashboard.stats.totalDailyRate.toString()}</span></div>
            <div className="flex justify-between"><span className="text-zinc-400">Total Dirt Balance</span><span className="font-bold">{dashboard.stats.totalDirtBalance.toString()}</span></div>
            <div className="flex justify-between"><span className="text-zinc-400">Total Mining Power</span><span className="font-bold">{dashboard.stats.totalMiningPower.toString()}</span></div>
          </div>

          <div className="space-y-3">
            <h3 className="text-lg font-bold text-emerald-400">Your Miners</h3>
            {dashboard.miners.length === 0 && (
              <p className="text-zinc-400">No miners created yet.</p>
            )}
            {dashboard.miners.map((m) => {
              const key = m.id.toString();
              const isEditing = !!editing[key];
              return (
                <div key={key} className="p-4 rounded-md bg-zinc-800">
                  <div className="flex items-center justify-between">
                    <div className="font-bold">{m.name} (ID: {m.id.toString()})</div>
                    <button
                      onClick={() => toggleEdit(m.id, m)}
                      className="px-3 py-1 text-sm font-bold text-white bg-zinc-700 rounded hover:bg-zinc-600"
                    >
                      {isEditing ? "Cancel" : "Edit"}
                    </button>
                  </div>
                  <div className="grid grid-cols-2 gap-2 mt-2 text-sm">
                    <div className="text-zinc-400">Power</div>
                    <div className="font-bold">{m.miningPower.toString()}</div>
                    <div className="text-zinc-400">Daily Rate</div>
                    <div className="font-bold">{m.dailyDirtRate.toString()}</div>
                    <div className="text-zinc-400">Dirt Balance</div>
                    <div className="font-bold">{m.dirtBalance.toString()}</div>
                    <div className="text-zinc-400">Active</div>
                    <div className="font-bold">{m.isActive ? "Yes" : "No"}</div>
                  </div>

                  {isEditing && (
                    <div className="mt-3 grid grid-cols-1 gap-2">
                      <input
                        className="w-full px-3 py-2 text-white bg-zinc-700 rounded-md focus:outline-none focus:ring-2 focus:ring-cyan-400"
                        placeholder="Name (optional)"
                        value={editName[key] ?? ""}
                        onChange={(e) => setEditName((p) => ({ ...p, [key]: e.target.value }))}
                      />
                      <input
                        className="w-full px-3 py-2 text-white bg-zinc-700 rounded-md focus:outline-none focus:ring-2 focus:ring-cyan-400"
                        placeholder="Mining Power (optional)"
                        value={editMiningPower[key] ?? ""}
                        onChange={(e) => setEditMiningPower((p) => ({ ...p, [key]: e.target.value }))}
                      />
                      <input
                        className="w-full px-3 py-2 text-white bg-zinc-700 rounded-md focus:outline-none focus:ring-2 focus:ring-cyan-400"
                        placeholder="Daily Dirt Rate (optional)"
                        value={editDailyRate[key] ?? ""}
                        onChange={(e) => setEditDailyRate((p) => ({ ...p, [key]: e.target.value }))}
                      />
                      <button
                        onClick={() => updateMiner(m.id)}
                        disabled={isSaving[key]}
                        className="px-4 py-2 font-bold text-white bg-cyan-600 rounded-lg hover:bg-cyan-700 disabled:opacity-50"
                      >
                        {isSaving[key] ? "Saving..." : "Save Changes"}
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </>
      )}
    </div>
  );
}


