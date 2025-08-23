## Frontend integration with ic_siwe_provider, mining, bridge and ICRC-2 ledgers

This guide explains how to connect a React frontend to your updated Motoko canisters using Sign-In with Ethereum (SIWE) via `ic_siwe_provider`, and how to interact with:

- `mining.mo` (business logic)
- `bridge-canister.mo` (mint to stable principals from bridge proofs)
- `drift_token.mo` (ICRC-2 deposit token)
- `ak69_token.mo` (ICRC-2 reward token)

It assumes:

- `ic_siwe_provider` is deployed on mainnet
- You have canister IDs for: provider, mining, bridge, drift ledger, ak69 ledger
- Frontend uses Vite + React

---

### 0) Architecture

```mermaid
sequenceDiagram
  autonumber
  participant User as User (MetaMask)
  participant FE as React + wagmi + ic-siwe-js
  participant ISP as ic_siwe_provider
  participant MIN as mining.mo
  participant BR as bridge-canister.mo
  participant T1 as drift_token (ICRC-2)
  participant T2 as ak69_token (ICRC-2)

  User->>FE: Connect wallet
  FE->>ISP: siwe_prepare_login(address)
  ISP-->>FE: SIWE message + nonce
  FE->>User: Request signature
  User-->>FE: Signature
  FE->>ISP: siwe_login(signature, address, session_pubkey, nonce)
  ISP-->>FE: DelegationChain (session identity)

  Note over FE: FE now signs calls; canisters see the stable principal

  FE->>T1: icrc2_approve(spender=MIN, amount)
  FE->>MIN: createMiner / topUpMiner
  MIN->>T1: icrc2_transfer_from(from=stable, to=MIN)
  T1-->>MIN: Ok

  loop Each block
    MIN->>T2: admin_mint(to=winner_stable, reward)
  end

  FE->>BR: processBurnProof(txId)
  BR->>T1: admin_mint(to=stable_principal, drift_amount)
```

Key points:

- The frontend signs as a delegated session identity, but canisters see the user’s stable IC principal derived from the ETH address.
- Approvals on the DRIFT ledger are made by the user’s stable principal (even though the frontend uses a delegated identity).
- The mining canister pulls DRIFT from the user’s stable principal using `icrc2_transfer_from` (after approval), and rewards winners in AK69 to their stable principal.
- The bridge canister mints DRIFT to the user’s stable principal derived from the burned EVM address.

---

### 1) Install dependencies

```bash
pnpm add ic-siwe-js ic-use-actor @dfinity/agent @dfinity/candid @dfinity/identity @dfinity/principal @tanstack/react-query wagmi viem react-hot-toast
```

---

### 2) Environment

Create `.env` at the project root:

```ini
VITE_CANISTER_ID_IC_SIWE_PROVIDER=aaaaa-aa   # replace
VITE_CANISTER_ID_MINING=aaaaa-aa             # replace
VITE_CANISTER_ID_BRIDGE=aaaaa-aa             # replace
VITE_CANISTER_ID_DRIFT=aaaaa-aa              # replace
VITE_CANISTER_ID_AK69=aaaaa-aa               # replace
```

Expose values in `vite.config.ts`:

```ts
import * as dotenv from "dotenv";
dotenv.config();

const pass = (k: string) => ({ [k]: JSON.stringify(process.env[k]) });

export default defineConfig({
  // ...
  define: {
    ...pass("VITE_CANISTER_ID_IC_SIWE_PROVIDER"),
    ...pass("VITE_CANISTER_ID_MINING"),
    ...pass("VITE_CANISTER_ID_BRIDGE"),
    ...pass("VITE_CANISTER_ID_DRIFT"),
    ...pass("VITE_CANISTER_ID_AK69"),
  },
});
```

---

### 3) SIWE provider and context setup

Wrap your app with providers to enable SIWE and query management.

```tsx
// src/main.tsx
import React from "react";
import ReactDOM from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider } from "wagmi";
import { SiweIdentityProvider } from "ic-siwe-js/react";
import { Toaster } from "react-hot-toast";
import App from "./App";
import { wagmiConfig } from "./wagmi";

const queryClient = new QueryClient();
const icSiweProviderId = import.meta.env
  .VITE_CANISTER_ID_IC_SIWE_PROVIDER as string;

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <SiweIdentityProvider canisterId={icSiweProviderId}>
          <App />
        </SiweIdentityProvider>
      </QueryClientProvider>
    </WagmiProvider>
    <Toaster />
  </React.StrictMode>
);
```

Minimal wagmi (WalletConnect example):

```ts
// src/wagmi.ts
import { createConfig, http } from "wagmi";
import { mainnet } from "wagmi/chains";
import { walletConnect } from "wagmi/connectors";

export const wagmiConfig = createConfig({
  chains: [mainnet],
  connectors: [walletConnect({ projectId: "YOUR_WC_ID" })],
  transports: { [mainnet.id]: http() },
});
```

---

### 4) Creating actors (mining, bridge, ledgers)

You can use `@dfinity/agent` directly, or `ic-use-actor` for React-friendly patterns.

```ts
// src/ic/actors.ts
import { Actor, HttpAgent } from "@dfinity/agent";
import { idlFactory as miningIdl } from "./idls/mining.did";
import { idlFactory as bridgeIdl } from "./idls/bridge.did";
import { idlFactory as icrcIdl } from "./idls/icrc2.did";
import { useSiwe } from "ic-siwe-js/react";

const miningId = import.meta.env.VITE_CANISTER_ID_MINING as string;
const bridgeId = import.meta.env.VITE_CANISTER_ID_BRIDGE as string;
const driftId = import.meta.env.VITE_CANISTER_ID_DRIFT as string;
const ak69Id = import.meta.env.VITE_CANISTER_ID_AK69 as string;

export function useActors() {
  const { identity } = useSiwe();
  const agent = new HttpAgent({ identity });
  if (import.meta.env.DEV) {
    agent.fetchRootKey().catch(() => {});
  }
  const mining = Actor.createActor(miningIdl, { agent, canisterId: miningId });
  const bridge = Actor.createActor(bridgeIdl, { agent, canisterId: bridgeId });
  const drift = Actor.createActor(icrcIdl, { agent, canisterId: driftId });
  const ak69 = Actor.createActor(icrcIdl, { agent, canisterId: ak69Id });
  return { mining, bridge, drift, ak69 };
}
```

Notes:

- Generate `*.did.js`/TS by adding canisters to `dfx.json` and running `dfx generate`, or place hand-authored IDL factories under `src/ic/idls/`.
- The `identity` from `ic-siwe-js` ensures calls are recognized as the user’s stable principal on-chain.

---

### 5) Login and session

Use `useSiwe` for login and to display the user’s IC principal.

```tsx
import { useSiwe } from "ic-siwe-js/react";

export function Login() {
  const { login, isLoggingIn, identity } = useSiwe();
  return (
    <div>
      <button onClick={login} disabled={isLoggingIn}>
        {isLoggingIn ? "Signing…" : "Sign-In with Ethereum"}
      </button>
      {identity && (
        <div>IC Principal: {identity.getPrincipal().toString()}</div>
      )}
    </div>
  );
}
```

---

### 6) Approve and deposit DRIFT to mining

Your canister `mining.mo` pulls DRIFT with `icrc2_transfer_from(from=stable, to=mining)`. Before calling `topUpMiner` or `createMiner`, the user must approve the mining canister as a spender on the DRIFT ledger.

```ts
import type { Principal } from "@dfinity/principal";
import { useActors } from "./ic/actors";
import { useSiwe } from "ic-siwe-js/react";

// ICRC-2 types (minimal)
type Subaccount = Uint8Array | number[] | null;
type Account = { owner: Principal; subaccount: Subaccount };

export function useMiningActions() {
  const { mining, drift } = useActors();
  const { identity } = useSiwe();

  const approveDrift = async (amount: bigint, miningCanisterId: string) => {
    const owner = identity!.getPrincipal();
    const spender: Account = {
      owner: miningCanisterId as unknown as Principal,
      subaccount: null,
    };
    // Many ledgers expose icrc2_approve({ from_subaccount, spender, amount, ... })
    // Replace with your generated types accordingly
    const res = await (drift as any).icrc2_approve({
      from_subaccount: null,
      spender,
      amount,
      expected_allowance: null,
      expires_at: null,
      fee: null,
      memo: null,
      created_at_time: null,
    });
    return res;
  };

  const createMiner = async (args: {
    name: string;
    miningPower: bigint;
    dailyDirtRate: bigint;
    initialDirtAmount: bigint;
  }) => {
    // After approval, the mining canister will pull the initial amount from the user's stable principal
    return await (mining as any).createMiner(args);
  };

  const topUpMiner = async (minerId: bigint, amount: bigint) => {
    return await (mining as any).topUpMiner(minerId, amount);
  };

  return { approveDrift, createMiner, topUpMiner };
}
```

Flow in UI:

1. User connects wallet and signs in with SIWE
2. User sets an amount and clicks “Approve DRIFT” (spender = mining canister)
3. User creates a miner or tops it up; the canister pulls DRIFT via `icrc2_transfer_from`

---

### 7) Reading balances and winners

DRIFT / AK69 balance for user’s account:

```ts
const owner = identity!.getPrincipal();
const account = { owner, subaccount: null };
const driftBal = await(drift as any).icrc1_balance_of(account);
const ak69Bal = await(ak69 as any).icrc1_balance_of(account);
```

Winners and rounds from `mining.mo`:

```ts
const rounds = await(mining as any).getLatestMiningRounds(10n);
```

---

### 8) Bridge flow (submit + process proofs)

Validators/owner call the bridge to process proofs and mint DRIFT to stable principals derived from EVM addresses.

```ts
const res = await(bridge as any).processBurnProof(txId);
```

Users will see tokens minted to their stable principal (same principal shown via `identity.getPrincipal()`), so balances appear directly when querying DRIFT ledger.

---

### 9) Error handling & session expiry

If a call fails with an “identity expired” error, prompt the user to sign in again. With `ic-use-actor` you can add interceptors; otherwise catch and handle errors:

```ts
try {
  await createMiner({ /* ... */ });
} catch (e: any) {
  // show toast / ask to re-login
}
``;

---

### 10) Troubleshooting

- Approval fails: Ensure the user is signed in via SIWE and is approving the **mining canister** as spender on the **DRIFT** ledger.
- Transfer_from fails: Check allowance and DRIFT balance, and confirm mining canister principal is correct.
- Missing balances: Query using `{ owner: identity.getPrincipal(), subaccount: null }`.
- Wrong principal: Confirm you’re using the principal from `useSiwe().identity.getPrincipal()`.
- Local dev:
  - Use local canister IDs and `agent.fetchRootKey()` in dev
  - If Candid/IDL types differ, re-run `dfx generate`

---

### 11) Security notes

- Assets are always held by the user’s stable principal derived from their ETH address; the frontend never holds keys.
- Never mint to or hold assets under a session-only principal. With SIWE, your calls are recognized as the stable principal via delegation.
- Keep `session_expires_in` (provider settings) reasonable (e.g., ≤ 1 week).

---

### 12) API quick reference (names may differ per your generated IDL)

- DRIFT (ICRC-2): `icrc1_balance_of`, `icrc1_fee`, `icrc2_approve`, `icrc2_transfer_from`
- AK69 (ICRC-2): `icrc1_balance_of`, `admin_mint` (controller only)
- Mining: `createMiner`, `topUpMiner`, `getLatestMiningRounds`, `getUserDashboard`
- Bridge: `processBurnProof`, `getBridgeTransaction`


```
