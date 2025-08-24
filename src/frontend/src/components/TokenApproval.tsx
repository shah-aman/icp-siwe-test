import { useEffect, useState } from "react";
import { useMiningActor } from "../ic/actor_providers";
import { createIcrc2ApproveActor } from "../ic/icrc2_approve_actor";
import { useStablePrincipal } from "../hooks/useStablePrincipal";
import canisterIds from "../ic/canister_ids.json";
import { Principal } from "@dfinity/principal";
import toast from "react-hot-toast";
import { useSiwe } from "ic-siwe-js/react";

// Helper to convert a token amount to its lowest denomination (e.g., 1.5 -> 1500000000)
const toSubunits = (amount: number, decimals: number) => {
  return BigInt(Math.floor(amount * 10 ** decimals));
};

export default function TokenApproval() {
  // Actors and identity
  const { actor: miningActor } = useMiningActor();
  const { stablePrincipal } = useStablePrincipal();
  const { identity } = useSiwe();

  // Local state for the form and UI feedback
  const [amount, setAmount] = useState("1.0");
  const [isApproving, setIsApproving] = useState(false);

  // Get the mining canister ID from our central config file
  const network = "mainnet";
  const miningCanisterIdString = canisterIds.mining[network];
  const isPlaceholderCanister = miningCanisterIdString === "aaaaa-aa";
  const miningCanisterId = Principal.fromText(miningCanisterIdString);

  // Resolve the authoritative DIRT ledger canister id from the mining canister
  const [dirtLedgerId, setDirtLedgerId] = useState<string | null>(null);

  useEffect(() => {
    const run = async () => {
      try {
        if (!miningActor) return;
        const principal = await miningActor.getDirtToken();
        setDirtLedgerId(principal.toText());
      } catch (e) {
        console.error("Failed to resolve DIRT ledger id", e);
        setDirtLedgerId(null);
      }
    };
    run();
  }, [miningActor]);

  const handleApproval = async () => {
    // 1. Pre-flight checks: Ensure all necessary actors and principals are available.
    if (!stablePrincipal || !identity) {
      toast.error("Cannot approve: Identity or user principal not available.");
      return;
    }

    const approvalAmount = parseFloat(amount);
    if (isNaN(approvalAmount) || approvalAmount <= 0) {
      toast.error("Please enter a valid, positive amount to approve.");
      return;
    }

    setIsApproving(true);
    const toastId = toast.loading("Sending approval transaction...");

    try {
      // 2. Prepare the arguments for the 'icrc2_approve' call.
      const args = {
        // 'from_subaccount' is optional. Use [] for the default subaccount.
        from_subaccount: [] as [],
        // The 'spender' is the canister you are authorizing. In this case, the mining canister.
        spender: {
          owner: miningCanisterId,
          subaccount: [] as [],
        },
        // Convert the human-readable amount to the token's lowest denomination (BigInt).
        // Assuming 9 decimals for the Drift token.
        amount: toSubunits(approvalAmount, 9),
        // 'expected_allowance' and 'expires_at' can be used for added security, but are optional.
        expected_allowance: [] as [],
        expires_at: [] as [],
        // 'fee', 'memo', and 'created_at_time' are optional as per the ICRC-2 standard.
        fee: [] as [],
        memo: [] as [],
        created_at_time: [] as [],
      };

      // 3. Use the resolved DIRT ledger id if available, otherwise fall back
      const ledgerId = dirtLedgerId ?? canisterIds.drift_token[network];
      if (!ledgerId) {
        throw new Error("DIRT ledger id unavailable");
      }
      const tolerantActor: any = createIcrc2ApproveActor(ledgerId, identity);
      const result = await tolerantActor.icrc2_approve(args);

      // 4. Handle the result
      if ("Ok" in result || "ok" in result) {
        toast.success(`Successfully approved spending of ${amount} DRIFT.`, {
          id: toastId,
        });
        setAmount("1.0"); // Reset form
      } else {
        // The error object contains detailed information about the failure.
        const errObj = (result as any).Err ?? (result as any).err;
        const errorMsg = errObj ? JSON.stringify(errObj) : "Unknown error";
        throw new Error(
          `Approval failed: ${errorMsg}`
        );
      }
    } catch (e: any) {
      toast.error(e.message, { id: toastId });
      console.error("Approval error:", e);
    } finally {
      setIsApproving(false);
    }
  };

  return (
    <div className="w-full max-w-2xl p-6 space-y-4 font-mono border-2 rounded-lg bg-zinc-900 border-zinc-700">
      <h2 className="text-xl font-bold text-center text-amber-400">
        ICRC-2 Token Approval
      </h2>
      <p className="text-sm text-center text-zinc-400">
        This demonstrates how to approve a canister (e.g., the Mining Canister)
        to spend your Drift Tokens. The approval is granted from your stable
        principal.
      </p>

      <div className="flex items-center gap-4 p-4 rounded-md bg-zinc-800">
        <label htmlFor="approval-amount" className="font-bold">
          Amount:
        </label>
        <input
          id="approval-amount"
          type="number"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="w-full px-3 py-2 text-right text-white bg-zinc-700 rounded-md focus:outline-none focus:ring-2 focus:ring-amber-400"
          min="0.0001"
          step="0.1"
        />
        <span className="font-bold text-zinc-400">DRIFT</span>
      </div>

      <button
        onClick={handleApproval}
        disabled={isApproving || !stablePrincipal || isPlaceholderCanister}
        className="w-full px-4 py-3 font-bold text-white bg-amber-600 rounded-lg hover:bg-amber-700 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {isApproving ? "Approving..." : "Approve Mining Canister"}
      </button>
      {isPlaceholderCanister && (
        <p className="text-xs text-center text-zinc-500">
          Note: Mining canister is not configured. Approval will not work.
        </p>
      )}
    </div>
  );
}
