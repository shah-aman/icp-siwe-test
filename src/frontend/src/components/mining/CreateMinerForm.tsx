import { useState } from "react";
import { useMiningActor } from "../../ic/actor_providers";
import toast from "react-hot-toast";
import { useSiwe } from "ic-siwe-js/react";
import { MinerCreationArgs } from "../../../declarations/mining/mining.did";
import canisterIds from "../../ic/canister_ids.json";
import { createMiningPatchedActor } from "../../ic/mining_patched_actor";

export default function CreateMinerForm() {
  const { identity } = useSiwe();
  const { actor: miningActor } = useMiningActor();

  const [name, setName] = useState("");
  const [miningPower, setMiningPower] = useState("10");
  const [initialDirt, setInitialDirt] = useState("100");
  const [dailyDirtRate, setDailyDirtRate] = useState("10");
  const [isCreating, setIsCreating] = useState(false);

  const handleCreateMiner = async () => {
    if (!identity) {
      toast.error("Identity not available.");
      return;
    }

    if (!name.trim()) {
      toast.error("Please enter a name for your miner.");
      return;
    }

    setIsCreating(true);
    const toastId = toast.loading("Creating miner...");

    try {
      // Use patched actor for createMiner
      const miningCanisterId = canisterIds.mining["mainnet"];
      const patchedActor: any = createMiningPatchedActor(miningCanisterId, identity);

      const args: MinerCreationArgs = {
        name: name.trim(),
        miningPower: BigInt(miningPower),
        initialDirtAmount: BigInt(initialDirt),
        dailyDirtRate: BigInt(dailyDirtRate),
      };

      const result = await patchedActor.createMiner(args);

      if ("ok" in result || "Ok" in result) {
        const minerId = result.ok || result.Ok;
        toast.success(`Miner created successfully! Miner ID: ${minerId}`, {
          id: toastId,
        });
        setName("");
      } else {
        const err = result.err || result.Err;
        const [errorKey, errorVal] = Object.entries(err)[0] as [string, unknown];
        throw new Error(`Failed to create miner: ${errorKey} - ${JSON.stringify(errorVal)}`);
      }
    } catch (e: any) {
      toast.error(e.message, { id: toastId });
      console.error("Miner creation error:", e);
    } finally {
      setIsCreating(false);
    }
  };

  return (
    <div className="w-full max-w-2xl p-6 space-y-4 font-mono border-2 rounded-lg bg-zinc-900 border-zinc-700">
      <h2 className="text-xl font-bold text-center text-cyan-400">
        Create a New Miner
      </h2>
      <p className="text-sm text-center text-zinc-400">
        This form demonstrates creating a miner from a pre-funded deposit
        account.
      </p>

      <div className="space-y-4">
        <div className="flex items-center gap-4">
          <label htmlFor="miner-name" className="font-bold w-36">
            Miner Name:
          </label>
          <input
            id="miner-name"
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full px-3 py-2 text-white bg-zinc-700 rounded-md focus:outline-none focus:ring-2 focus:ring-cyan-400"
            placeholder="e.g., 'My First Miner'"
          />
        </div>
        <div className="flex items-center gap-4">
          <label htmlFor="mining-power" className="font-bold w-36">
            Mining Power:
          </label>
          <input
            id="mining-power"
            type="number"
            value={miningPower}
            onChange={(e) => setMiningPower(e.target.value)}
            className="w-full px-3 py-2 text-right text-white bg-zinc-700 rounded-md focus:outline-none focus:ring-2 focus:ring-cyan-400"
          />
        </div>
        <div className="flex items-center gap-4">
          <label htmlFor="initial-dirt" className="font-bold w-36">
            Initial DIRT:
          </label>
          <input
            id="initial-dirt"
            type="number"
            value={initialDirt}
            onChange={(e) => setInitialDirt(e.target.value)}
            className="w-full px-3 py-2 text-right text-white bg-zinc-700 rounded-md focus:outline-none focus:ring-2 focus:ring-cyan-400"
          />
        </div>
        <div className="flex items-center gap-4">
          <label htmlFor="daily-dirt-rate" className="font-bold w-36">
            Daily DIRT Rate:
          </label>
          <input
            id="daily-dirt-rate"
            type="number"
            value={dailyDirtRate}
            onChange={(e) => setDailyDirtRate(e.target.value)}
            className="w-full px-3 py-2 text-right text-white bg-zinc-700 rounded-md focus:outline-none focus:ring-2 focus:ring-cyan-400"
          />
        </div>
      </div>

      <button
        onClick={handleCreateMiner}
        disabled={isCreating || !identity}
        className="w-full px-4 py-3 font-bold text-white bg-cyan-600 rounded-lg hover:bg-cyan-700 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {isCreating ? "Creating Miner..." : "Create Miner"}
      </button>
    </div>
  );
}
