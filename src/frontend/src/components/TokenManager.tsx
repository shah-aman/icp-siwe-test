import { useEffect, useState } from "react";
import { useAccount } from "wagmi";
import { useAk69TokenActor, useDriftTokenActor } from "../ic/actor_providers";
import { useStablePrincipal } from "../hooks/useStablePrincipal";
import { useSiwe } from "ic-siwe-js/react";

// Helper to format BigInt balance from a canister to a display string.
const formatBalance = (balance: bigint, decimals: number): string => {
  return (Number(balance) / 10 ** decimals).toFixed(4);
};

export default function TokenManager() {
  const { address } = useAccount();
  const { identity } = useSiwe();

  // Use our production-style hooks
  const { actor: driftTokenActor } = useDriftTokenActor();
  const { actor: ak69TokenActor } = useAk69TokenActor();
  const {
    stablePrincipal,
    loading: stablePrincipalLoading,
    error: stablePrincipalError,
  } = useStablePrincipal();

  // Local state for balances and UI feedback
  const [balances, setBalances] = useState<{
    drift: string | null;
    ak69: string | null;
  }>({ drift: null, ak69: null });
  const [loadingBalances, setLoadingBalances] = useState(false);
  const [balanceError, setBalanceError] = useState<string | null>(null);

  const fetchBalances = async () => {
    if (!stablePrincipal || !driftTokenActor || !ak69TokenActor) {
      setBalanceError("Actors not ready or stable principal not derived.");
      return;
    }

    setLoadingBalances(true);
    setBalanceError(null);

    try {
      // subaccount is an opt type: [] | [Subaccount]. Use [] as [] to satisfy TS.
      const account = { owner: stablePrincipal, subaccount: [] as [] };

      // Fetch balances in parallel for efficiency
      const [driftBalanceResult, ak69BalanceResult] = await Promise.all([
        driftTokenActor.icrc1_balance_of(account),
        ak69TokenActor.icrc1_balance_of(account),
      ]);

      setBalances({
        drift: formatBalance(driftBalanceResult, 9), // Assuming 9 decimals
        ak69: formatBalance(ak69BalanceResult, 9), // Assuming 9 decimals
      });
    } catch (e: any) {
      setBalanceError(`Error fetching balances: ${e.message}`);
      console.error("Balance fetch error:", e);
    } finally {
      setLoadingBalances(false);
    }
  };

  // Automatically fetch balances when the stable principal is available
  useEffect(() => {
    if (stablePrincipal && driftTokenActor && ak69TokenActor) {
      fetchBalances();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stablePrincipal, driftTokenActor, ak69TokenActor]);

  // Render nothing until the user has an identity (is logged in)
  if (!identity) {
    return (
      <div className="p-6 text-center border-2 rounded-lg bg-zinc-900 border-zinc-700">
        <p className="text-zinc-400">Please sign in to manage your tokens.</p>
      </div>
    );
  }

  return (
    <div className="w-full max-w-2xl p-6 space-y-4 font-mono border-2 rounded-lg bg-zinc-900 border-zinc-700">
      <h2 className="text-2xl font-bold text-center text-emerald-400">
        Token Dashboard
      </h2>

      {/* --- Identity Information --- */}
      <div className="p-4 space-y-2 text-sm break-all rounded-md bg-zinc-800">
        <p>
          <strong>ETH Address:</strong> {address}
        </p>
        <p>
          <strong>Session Principal:</strong> {identity.getPrincipal().toText()}
        </p>
        <p>
          <strong>Stable Principal:</strong>{" "}
          {stablePrincipalLoading
            ? "Deriving..."
            : stablePrincipal?.toText() || "Not available"}
          {stablePrincipalError && (
            <span className="ml-2 text-red-400">
              ({stablePrincipalError})
            </span>
          )}
        </p>
      </div>

      {/* --- Balances Display --- */}
      <div className="p-4 space-y-3 rounded-md bg-zinc-800">
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-bold">Your Balances</h3>
          <button
            onClick={fetchBalances}
            disabled={loadingBalances || !stablePrincipal}
            className="px-3 py-1 text-sm font-bold text-white bg-blue-600 rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {loadingBalances ? "Refreshing..." : "Refresh"}
          </button>
        </div>
        {balanceError && <p className="text-red-400">{balanceError}</p>}
        <div className="flex justify-between">
          <span className="text-zinc-400">Drift Token:</span>
          <span className="font-bold text-emerald-400">
            {balances.drift ?? "N/A"} DRIFT
          </span>
        </div>
        <div className="flex justify-between">
          <span className="text-zinc-400">AK69 Token:</span>
          <span className="font-bold text-emerald-400">
            {balances.ak69 ?? "N/A"} AK69
          </span>
        </div>
      </div>
    </div>
  );
}
