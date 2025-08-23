import { useEffect, useState } from "react";
import { Principal } from "@dfinity/principal";
import { useSiweProviderActor } from "../ic/actor_providers";
import { useAccount } from "wagmi";

/**
 * A hook to derive the stable principal from the user's Ethereum address.
 * It uses the globally provided siwe_provider actor.
 *
 * @returns An object containing the stable principal, loading state, and any errors.
 */
export function useStablePrincipal() {
  const { address } = useAccount();
  const { actor: siweProviderActor } = useSiweProviderActor();
  const [stablePrincipal, setStablePrincipal] = useState<Principal | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const derivePrincipal = async () => {
      if (!address || !siweProviderActor) {
        setStablePrincipal(null);
        return;
      }

      setLoading(true);
      setError(null);
      try {
        const response = await siweProviderActor.get_principal(address);
        if ("Ok" in response) {
          const bytes = new Uint8Array(response.Ok as unknown as ArrayBufferLike);
          const principal = Principal.fromUint8Array(bytes);
          setStablePrincipal(principal);
        } else {
          throw new Error(response.Err);
        }
      } catch (e: any) {
        setError(`Failed to derive stable principal: ${e.message}`);
        console.error("Stable principal derivation error:", e);
        setStablePrincipal(null);
      } finally {
        setLoading(false);
      }
    };

    derivePrincipal();
  }, [address, siweProviderActor]);

  return { stablePrincipal, loading, error };
}
