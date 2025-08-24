import { Actor, HttpAgent } from "@dfinity/agent";
import type { Identity } from "@dfinity/agent";
import { IDL } from "@dfinity/candid";

// Create a minimal ICRC-2 approve actor with tolerant result variant keys
export function createIcrc2ApproveActor(canisterId: string, identity?: Identity) {
  const agent = new HttpAgent({ host: "https://icp-api.io", identity });

  const idlFactory = ({ IDL }: { IDL: any }) => {
    const Subaccount = IDL.Vec(IDL.Nat8);
    const Account = IDL.Record({ owner: IDL.Principal, subaccount: IDL.Opt(Subaccount) });
    const Tokens = IDL.Nat;
    const Memo = IDL.Vec(IDL.Nat8);
    const Timestamp = IDL.Nat64;

    const ApproveError = IDL.Variant({
      InsufficientFunds: IDL.Record({ balance: Tokens }),
      TooOld: IDL.Null,
      Duplicate: IDL.Record({ duplicate_of: IDL.Nat }),
      BadFee: IDL.Record({ expected_fee: Tokens }),
      AllowanceChanged: IDL.Record({ current_allowance: Tokens }),
      CreatedInFuture: IDL.Record({ ledger_time: Timestamp }),
      TemporarilyUnavailable: IDL.Null,
      Expired: IDL.Record({ ledger_time: Timestamp }),
      GenericError: IDL.Record({ message: IDL.Text, error_code: IDL.Nat }),
    });

    const ApproveArgs = IDL.Record({
      spender: Account,
      amount: Tokens,
      expected_allowance: IDL.Opt(Tokens),
      expires_at: IDL.Opt(Timestamp),
      fee: IDL.Opt(Tokens),
      memo: IDL.Opt(Memo),
      from_subaccount: IDL.Opt(Subaccount),
      created_at_time: IDL.Opt(Timestamp),
    });

    // Accept both 'Ok'/'ok' and 'Err'/'err' to avoid decode errors across ledgers
    // Use Reserved for both Ok/ok and Err/err to tolerate any shape
    const ApproveResult = IDL.Variant({
      Ok: IDL.Reserved,
      Err: IDL.Reserved,
      ok: IDL.Reserved,
      err: IDL.Reserved,
    });

    return IDL.Service({
      icrc2_approve: IDL.Func([ApproveArgs], [ApproveResult], []),
    });
  };

  return Actor.createActor(idlFactory as any, { agent, canisterId });
}


