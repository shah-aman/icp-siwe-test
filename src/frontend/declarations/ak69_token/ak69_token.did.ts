import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';

export interface Account { 'owner' : Principal, 'subaccount' : [] | [Subaccount] }
export interface Allowance {
  'allowance' : Tokens,
  'expires_at' : [] | [Timestamp],
}
export type ApproveError = { 'InsufficientFunds' : { 'balance' : Tokens } } |
  { 'TooOld' : null } |
  { 'Duplicate' : { 'duplicate_of' : TxIndex } } |
  { 'BadFee' : { 'expected_fee' : Tokens } } |
  { 'AllowanceChanged' : { 'current_allowance' : Tokens } } |
  { 'CreatedInFuture' : { 'ledger_time' : Timestamp } } |
  { 'TemporarilyUnavailable' : null } |
  { 'Expired' : { 'ledger_time' : Timestamp } } |
  { 'GenericError' : { 'message' : string, 'error_code' : bigint } };
export type Duration = bigint;
export type Memo = Array<number>;
export type Subaccount = Array<number>;
export type Timestamp = bigint;
export type Tokens = bigint;
export type TransferError = { 'InsufficientFunds' : { 'balance' : Tokens } } |
  { 'TooOld' : null } |
  { 'BadBurn' : { 'min_burn_amount' : Tokens } } |
  { 'Duplicate' : { 'duplicate_of' : TxIndex } } |
  { 'BadFee' : { 'expected_fee' : Tokens } } |
  { 'CreatedInFuture' : { 'ledger_time' : Timestamp } } |
  { 'TemporarilyUnavailable' : null } |
  { 'GenericError' : { 'message' : string, 'error_code' : bigint } };
export type TransferFromError = {
    'InsufficientFunds' : { 'balance' : Tokens }
  } |
  { 'TooOld' : null } |
  { 'Duplicate' : { 'duplicate_of' : TxIndex } } |
  { 'BadFee' : { 'expected_fee' : Tokens } } |
  { 'InsufficientAllowance' : { 'allowance' : Tokens } } |
  { 'CreatedInFuture' : { 'ledger_time' : Timestamp } } |
  { 'TemporarilyUnavailable' : null } |
  { 'GenericError' : { 'message' : string, 'error_code' : bigint } };
export type TxIndex = bigint;
export type Value = { 'Nat' : bigint } |
  { 'Blob' : Array<number> } |
  { 'Text' : string };
export interface _SERVICE {
  'icrc1_balance_of' : ActorMethod<[Account], Tokens>,
  'icrc1_decimals' : ActorMethod<[], number>,
  'icrc1_fee' : ActorMethod<[], Tokens>,
  'icrc1_metadata' : ActorMethod<[], Array<[string, Value]>>,
  'icrc1_name' : ActorMethod<[], string>,
  'icrc1_symbol' : ActorMethod<[], string>,
  'icrc1_supported_standards' : ActorMethod<
    [],
    Array<{ 'url' : string, 'name' : string }>
  >,
  'icrc1_total_supply' : ActorMethod<[], Tokens>,
  'icrc1_transfer' : ActorMethod<
    [
      {
        'to' : Account,
        'fee' : [] | [Tokens],
        'memo' : [] | [Memo],
        'from_subaccount' : [] | [Subaccount],
        'created_at_time' : [] | [Timestamp],
        'amount' : Tokens,
      },
    ],
    { 'Ok' : TxIndex } |
      { 'Err' : TransferError }
  >,
  'icrc2_allowance' : ActorMethod<
    [{ 'account' : Account, 'spender' : Account }],
    Allowance
  >,
  'icrc2_approve' : ActorMethod<
    [
      {
        'fee' : [] | [Tokens],
        'memo' : [] | [Memo],
        'from_subaccount' : [] | [Subaccount],
        'created_at_time' : [] | [Timestamp],
        'amount' : Tokens,
        'expected_allowance' : [] | [Tokens],
        'expires_at' : [] | [Timestamp],
        'spender' : Account,
      },
    ],
    { 'Ok' : TxIndex } |
      { 'Err' : ApproveError }
  >,
  'icrc2_transfer_from' : ActorMethod<
    [
      {
        'to' : Account,
        'fee' : [] | [Tokens],
        'spender_subaccount' : [] | [Subaccount],
        'from' : Account,
        'memo' : [] | [Memo],
        'created_at_time' : [] | [Timestamp],
        'amount' : Tokens,
      },
    ],
    { 'Ok' : TxIndex } |
      { 'Err' : TransferFromError }
  >,
}
export const idlFactory = ({ IDL }) => {
  const Subaccount = IDL.Vec(IDL.Nat8);
  const Account = IDL.Record({
    'owner' : IDL.Principal,
    'subaccount' : IDL.Opt(Subaccount),
  });
  const Tokens = IDL.Nat;
  const Timestamp = IDL.Nat64;
  const Value = IDL.Variant({
    'Nat' : IDL.Nat,
    'Blob' : IDL.Vec(IDL.Nat8),
    'Text' : IDL.Text,
  });
  const Memo = IDL.Vec(IDL.Nat8);
  const TransferError = IDL.Variant({
    'InsufficientFunds' : IDL.Record({ 'balance' : Tokens }),
    'TooOld' : IDL.Null,
    'BadBurn' : IDL.Record({ 'min_burn_amount' : Tokens }),
    'Duplicate' : IDL.Record({ 'duplicate_of' : IDL.Nat }),
    'BadFee' : IDL.Record({ 'expected_fee' : Tokens }),
    'CreatedInFuture' : IDL.Record({ 'ledger_time' : Timestamp }),
    'TemporarilyUnavailable' : IDL.Null,
    'GenericError' : IDL.Record({
      'message' : IDL.Text,
      'error_code' : IDL.Nat,
    }),
  });
  const TxIndex = IDL.Nat;
  const Allowance = IDL.Record({
    'allowance' : Tokens,
    'expires_at' : IDL.Opt(Timestamp),
  });
  const ApproveError = IDL.Variant({
    'InsufficientFunds' : IDL.Record({ 'balance' : Tokens }),
    'TooOld' : IDL.Null,
    'Duplicate' : IDL.Record({ 'duplicate_of' : TxIndex }),
    'BadFee' : IDL.Record({ 'expected_fee' : Tokens }),
    'AllowanceChanged' : IDL.Record({ 'current_allowance' : Tokens }),
    'CreatedInFuture' : IDL.Record({ 'ledger_time' : Timestamp }),
    'TemporarilyUnavailable' : IDL.Null,
    'Expired' : IDL.Record({ 'ledger_time' : Timestamp }),
    'GenericError' : IDL.Record({
      'message' : IDL.Text,
      'error_code' : IDL.Nat,
    }),
  });
  const TransferFromError = IDL.Variant({
    'InsufficientFunds' : IDL.Record({ 'balance' : Tokens }),
    'TooOld' : IDL.Null,
    'Duplicate' : IDL.Record({ 'duplicate_of' : TxIndex }),
    'BadFee' : IDL.Record({ 'expected_fee' : Tokens }),
    'InsufficientAllowance' : IDL.Record({ 'allowance' : Tokens }),
    'CreatedInFuture' : IDL.Record({ 'ledger_time' : Timestamp }),
    'TemporarilyUnavailable' : IDL.Null,
    'GenericError' : IDL.Record({
      'message' : IDL.Text,
      'error_code' : IDL.Nat,
    }),
  });
  return IDL.Service({
    'icrc1_balance_of' : IDL.Func([Account], [Tokens], ['query']),
    'icrc1_decimals' : IDL.Func([], [IDL.Nat8], ['query']),
    'icrc1_fee' : IDL.Func([], [Tokens], ['query']),
    'icrc1_metadata' : IDL.Func(
        [],
        [IDL.Vec(IDL.Tuple(IDL.Text, Value))],
        ['query'],
      ),
    'icrc1_name' : IDL.Func([], [IDL.Text], ['query']),
    'icrc1_symbol' : IDL.Func([], [IDL.Text], ['query']),
    'icrc1_supported_standards' : IDL.Func(
        [],
        [IDL.Vec(IDL.Record({ 'url' : IDL.Text, 'name' : IDL.Text }))],
        ['query'],
      ),
    'icrc1_total_supply' : IDL.Func([], [Tokens], ['query']),
    'icrc1_transfer' : IDL.Func(
        [
          IDL.Record({
            'to' : Account,
            'fee' : IDL.Opt(Tokens),
            'memo' : IDL.Opt(Memo),
            'from_subaccount' : IDL.Opt(Subaccount),
            'created_at_time' : IDL.Opt(Timestamp),
            'amount' : Tokens,
          }),
        ],
        [IDL.Variant({ 'Ok' : TxIndex, 'Err' : TransferError })],
        [],
      ),
    'icrc2_allowance' : IDL.Func(
        [IDL.Record({ 'account' : Account, 'spender' : Account })],
        [Allowance],
        ['query'],
      ),
    'icrc2_approve' : IDL.Func(
        [
          IDL.Record({
            'fee' : IDL.Opt(Tokens),
            'memo' : IDL.Opt(Memo),
            'from_subaccount' : IDL.Opt(Subaccount),
            'created_at_time' : IDL.Opt(Timestamp),
            'amount' : Tokens,
            'expected_allowance' : IDL.Opt(Tokens),
            'expires_at' : IDL.Opt(Timestamp),
            'spender' : Account,
          }),
        ],
        [IDL.Variant({ 'Ok' : TxIndex, 'Err' : ApproveError })],
        [],
      ),
    'icrc2_transfer_from' : IDL.Func(
        [
          IDL.Record({
            'to' : Account,
            'fee' : IDL.Opt(Tokens),
            'spender_subaccount' : IDL.Opt(Subaccount),
            'from' : Account,
            'memo' : IDL.Opt(Memo),
            'created_at_time' : IDL.Opt(Timestamp),
            'amount' : Tokens,
          }),
        ],
        [IDL.Variant({ 'Ok' : TxIndex, 'Err' : TransferFromError })],
        [],
      ),
  });
};
export const init = ({ IDL }) => { return []; };
