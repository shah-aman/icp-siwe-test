import "./index.css";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

import ActorProviders from "./ic/actor_providers.tsx";
import App from "./App.tsx";
import AuthGuard from "./AuthGuard.tsx";
import React from "react";
import ReactDOM from "react-dom/client";
import { SiweIdentityProvider } from "ic-siwe-js/react";
import { Toaster } from "react-hot-toast";
import { WagmiProvider } from "wagmi";
import { wagmiConfig } from "./wagmi/wagmi.config.ts";
import canisterIds from "./ic/canister_ids.json";

const queryClient = new QueryClient();

const network = "mainnet";
const siweProviderCanisterId = canisterIds.ic_siwe_provider[network];
const host = "https://icp-api.io";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <SiweIdentityProvider canisterId={siweProviderCanisterId} httpAgentOptions={{ host }}>
          <ActorProviders>
            <AuthGuard>
              <App />
            </AuthGuard>
          </ActorProviders>
        </SiweIdentityProvider>
      </QueryClientProvider>
    </WagmiProvider>
    <Toaster />
  </React.StrictMode>
);
