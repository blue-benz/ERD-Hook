# Overview

ERD-Hook is a Uniswap v4 hook + incentives stack that routes external/protocol revenue into deterministic LP rewards.

## Problem

Liquidity mining usually depends on token emissions that are disconnected from real protocol cash flow.

## Primitive

ERD-Hook ties incentives to external revenue streams:

1. Revenue enters through `RevenueRouter`.
2. Program rules live in `IncentiveController`.
3. LP contribution updates are emitted by `IncentivesHook` and accounted in `RewardsVault`.
4. LPs claim rewards on-chain using accumulator math, without iterating over all LPs.

## Supported Distribution Modes

1. `STREAMING`: continuous per-second emissions with bounded-gas claims.
2. `EPOCH`: fixed-window emissions with explicit epoch boundaries and accumulator settlement.

## Repository Layout

- `src/`: Solidity contracts.
- `test/`: unit, edge, fuzz, and integration tests.
- `script/`: Forge deploy/demo scripts.
- `scripts/`: bootstrap, demo wrappers, ABI export, commit checks.
- `frontend/`: Incentives Console.
- `shared/`: shared ABIs and TS types.
