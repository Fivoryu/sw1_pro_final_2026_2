# RoomForge local reservation escrow

This package contains a local Hardhat demonstration of a reservation escrow that moves a configurable ERC-20 test asset. It is not a payment system, does not represent a real-world token value, and must not be deployed to a testnet or used with real funds. The only configured network is Hardhat's ephemeral local network (`chainId: 31337`). There is no RPC client or relayer in this package.

The API remains authoritative for reservation records. The escrow validates signed actions and moves the local test token; backend event/receipt reconciliation is outside this work unit. The broader API document remains a proposal and is not approved by this implementation.

## Local toolchain

Exact dependency versions are pinned in `package.json` and `package-lock.json`:

- Solidity `0.8.28`, via the npm `solc` package.
- Hardhat `2.22.17`, ethers plugin `3.0.8`, chai matchers `2.0.8`, ethers `6.13.4`.
- OpenZeppelin Contracts `5.2.0`.
- TypeScript `5.7.2`, ts-node `10.9.2`, Chai `4.5.0`.

Hardhat is configured to compile from the installed `solc/soljson.js` package. It does not need to contact a Solidity compiler host. Install the pinned dependencies from this directory, then run only the local tests:

```sh
npm ci --ignore-scripts --no-audit --no-fund
npx --no-install hardhat test
```

Hardhat test runs use an ephemeral local chain and deploy fixtures only inside that test process. No standalone node, testnet, external RPC, or real funds are involved.

## Token units

Two local-only OpenZeppelin ERC-20 test assets are provided; only their owner can mint:

- `RoomForgeTestToken` (`RFT`), with **2 decimals**, following the commercial money convention.
- `MockUSDT` (`USDT`), with **6 decimals**, mirroring a USDT-like stablecoin asset.

The escrow constructor accepts any token reporting **at least 2 decimals** and reverts with `InvalidTokenConfiguration` for fewer (commercial money is expressed with 2 decimals, so nothing below that floor is admitted).

The escrow only moves raw base units in the token's own scale. Converting a displayed commercial amount to base units is the **caller's responsibility** (the backend, via `TOKEN_UNIT_SCALES` in `backend/app/core/money.py`: BOB/USD ×100, USDT ×1e6). For example, `BOB 38.42` is `3,842` base units of the 2-decimal token, and `USDT 1.00` is `1,000,000` base units of `MockUSDT`. Do not use floating-point arithmetic.

## EIP-712 action

`ReservationEscrow` constructor:

```solidity
constructor(address tokenAddress, address signerAddress)
```

Both addresses are fixed at construction. `signerAddress` is the backend authorization signer; no signing key is embedded in the contract. The EIP-712 domain is:

```text
name:              RoomForgeReservationEscrow
version:           1
chainId:           current chain id
verifyingContract: this escrow address
```

The typed data primary type is:

```text
ReservationAction(
  bytes32 reservationId,
  bytes32 listingId,
  address customer,
  address agency,
  address actor,
  uint8 action,
  uint256 amount,
  uint64 deadline,
  uint256 nonce
)
```

`amount` is the configured deposit in token base units; `0` represents a nullable/no-deposit listing. The backend/API integration must use a deterministic hash for each reservation and listing ID. This local implementation's test convention is `keccak256(UTF-8 identifier bytes)`; the backend must use the same canonicalization before signing. Nonces increase independently per reservation and are consumed only by successful signed actions; expiry also advances the reservation nonce.

Action values follow the Solidity `Action` enum: `Deposit = 0`, `Accept = 1`, `Reject = 2`, `Cancel = 3`. Every permit-protected call requires the transaction sender to equal the signed `actor`. Deposit is customer-only; accept/reject are agency-wallet-only; cancel may be sent by either the reservation customer or its bound agency wallet. There is no relayer path.

All signed actions must be mined **strictly before** their signed deadline. Positive-deposit accept/reject requires the exact configured amount already held in escrow. A first authorized accept/reject/cancel for a zero-deposit reservation creates its on-chain record and event without a registration transaction. Cancel may likewise be the first action when a positive amount was configured but never deposited; it refunds zero and emits `Cancelled`. An untouched no-deposit reservation needs no chain record and expires in the backend.

## ABI-facing functions

| Function | Behavior |
|---|---|
| `deposit(ReservationAction, bytes)` | Customer submits a valid deposit permit, approves the exact amount, and transfers the configured positive amount into escrow. Initializes the reservation as pending when this is its first action. |
| `accept(ReservationAction, bytes)` | Bound agency wallet submits a valid permit before deadline. Requires any configured positive deposit to be present, transfers it to the agency, and records `Accepted`. There is deliberately no accepted-release function. |
| `reject(ReservationAction, bytes)` | Bound agency wallet submits a valid permit before deadline. Requires a configured positive deposit to be present, refunds any held amount to the customer, and records `Rejected`. Zero-deposit rejection still records the action. |
| `cancel(ReservationAction, bytes)` | Customer or bound agency wallet submits a valid permit before deadline. Refunds any held amount and records `Cancelled`, including when cancellation is the first action. |
| `expire(bytes32 reservationId)` | Permissionless at or after the deadline, but only for a deposited pending reservation. Refunds the customer and records `Expired`; accepted reservations cannot expire. |
| `reservation(bytes32)` | Reads the reservation's listing, customer, agency, configured amount, deadline, state, and currently escrowed amount. |
| `nonces(bytes32)` | Reads the next expected EIP-712 nonce for that reservation. |

Terminal state and nonce updates occur before token transfers; `SafeERC20` and `ReentrancyGuard` protect token interactions. A failed token transfer reverts the whole transaction, including the state and nonce updates.

## Events

- `Deposited(reservationId, listingId, customer, amount, nonce)`
- `Accepted(reservationId, listingId, agency, amount, nonce)`
- `Rejected(reservationId, listingId, customer, refundAmount, nonce)`
- `Cancelled(reservationId, listingId, actor, refundAmount, nonce)`
- `Expired(reservationId, listingId, customer, refundAmount, nonce)`

Decision, cancellation, and expiry events are emitted even when the refunded/transferred amount is zero. For expiry, the event nonce is the reservation's next nonce before expiry consumes it.

## Local test coverage

The Hardhat suite covers token decimals/mint access for both test assets, the token-configuration floor (deployment rejects tokens below 2 decimals), exact scaling with the 2-decimal token and the 6-decimal USDT-like token (deposit/accept/reject/cancel/expiry in exact base units), EIP-712 domain/signer/actor/deadline/nonce checks, reservation isolation and immutable terms, deposit/allowance/replay rules, first-action zero-deposit transitions, positive-deposit accept/reject/cancel/expiry, exact refunds and payouts, accepted-state locking, atomic rollback on transfer failure, and a token-callback reentrancy attempt.
