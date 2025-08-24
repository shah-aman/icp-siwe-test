/* eslint-disable react-refresh/only-export-components */
import { ActorProvider, createActorContext, createUseActorHook } from "ic-use-actor";
import { idlFactory as siweProviderIdlFactory } from "../../../ic_siwe_provider/declarations";
import { idlFactory as driftTokenIdlFactory } from "../../declarations/drift_token";
import { idlFactory as ak69TokenIdlFactory } from "../../declarations/ak69_token";
import * as miningIdl from "../../declarations/mining/mining.did.js";
import canisterIds from "./canister_ids.json";

import { ReactNode } from "react";
import { useSiwe } from "ic-siwe-js/react";
import type { _SERVICE as SiweProviderService } from "../../../ic_siwe_provider/declarations/ic_siwe_provider.did.d";
import type { _SERVICE as TokenService } from "../../declarations/drift_token";
import type { _SERVICE as MiningService } from "../../declarations/mining";

const network = "mainnet";
const host = "https://icp-api.io";

// --- 1. Create Actor Contexts ---
// Each actor needs its own React Context.
const siweProviderContext = createActorContext<SiweProviderService>();
const driftTokenContext = createActorContext<TokenService>();
const ak69TokenContext = createActorContext<TokenService>();
const miningContext = createActorContext<MiningService>();

// --- 2. Create Actor Hooks ---
// These hooks are how your components will access the actors.
export const useSiweProviderActor = createUseActorHook<SiweProviderService>(siweProviderContext);
export const useDriftTokenActor = createUseActorHook<TokenService>(driftTokenContext);
export const useAk69TokenActor = createUseActorHook<TokenService>(ak69TokenContext);
export const useMiningActor = createUseActorHook<MiningService>(miningContext);

// --- 3. Create the MultiActorProvider Component ---
// This component will wrap your application and provide all the actors.
export default function ActorProviders({ children }: { children: ReactNode }) {
  const { identity } = useSiwe();

  // Get the correct canister IDs based on the current network.
  const siwe_provider_canister_id = canisterIds.ic_siwe_provider[network];
  const drift_token_canister_id = canisterIds.drift_token[network];
  const ak69_token_canister_id = canisterIds.ak69_token[network];
  const mining_canister_id = canisterIds.mining[network];
  const isMiningCanisterPlaceholder = mining_canister_id === "aaaaa-aa";

  // Note: It's important that the ActorProvider is re-rendered when the identity changes.
  // The `key` prop on ActorProvider ensures this happens correctly.
  return (
    <ActorProvider<SiweProviderService>
      key={`siwe_provider_${identity?.getPrincipal().toText()}`}
      canisterId={siwe_provider_canister_id}
      context={siweProviderContext}
      identity={identity}
      idlFactory={siweProviderIdlFactory}
      httpAgentOptions={{ host }}
    >
      <ActorProvider<TokenService>
        key={`drift_token_${identity?.getPrincipal().toText()}`}
        canisterId={drift_token_canister_id}
        context={driftTokenContext}
        identity={identity}
        idlFactory={driftTokenIdlFactory}
        httpAgentOptions={{ host }}
      >
        <ActorProvider<TokenService>
          key={`ak69_token_${identity?.getPrincipal().toText()}`}
          canisterId={ak69_token_canister_id}
          context={ak69TokenContext}
          identity={identity}
          idlFactory={ak69TokenIdlFactory}
          httpAgentOptions={{ host }}
        >
          {isMiningCanisterPlaceholder ? (
            children
          ) : (
            <ActorProvider<MiningService>
              key={`mining_${identity?.getPrincipal().toText()}`}
              canisterId={mining_canister_id}
              context={miningContext}
              identity={identity}
              idlFactory={miningIdl.idlFactory}
              httpAgentOptions={{ host }}
            >
              {children}
            </ActorProvider>
          )}
        </ActorProvider>
      </ActorProvider>
    </ActorProvider>
  );
}
