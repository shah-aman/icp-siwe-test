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
import { HttpAgent } from "@dfinity/agent";

const queryClient = new QueryClient();

// Use the environment variable provided by Vite to determine the network
const networkEnv = process.env.DFX_NETWORK || "local";
const network = networkEnv === "ic" ? "mainnet" : "local";
const isMainnet = network === "mainnet";

const siweProviderCanisterId = canisterIds.ic_siwe_provider[network];
const host = isMainnet ? "https://icp-api.io" : "http://127.0.0.1:4943";

const agent = new HttpAgent({
  host: "http://127.0.0.1:5173", // URL of the Vite dev server
});

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <SiweIdentityProvider agent={agent}>
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
