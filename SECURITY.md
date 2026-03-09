# Security Policy

## Scope

Contracts under `src/`:

- `IncentivesHook`
- `IncentiveController`
- `RevenueRouter`
- `RewardsVault`
- `WeightingLibrary`

## Threat Model Summary

- Hook callback spoofing.
- Unauthorized config/funding operations.
- Reward accounting drift and double-claim.
- Reentrancy in claim paths.
- Liquidity flash farming and rapid churn.

## Implemented Mitigations

- PoolManager-only hook entrypoints (`BaseHook`).
- Hook-only accounting ingress in controller.
- Delayed config updates via queue/execute.
- Reentrancy guard on reward claims.
- Warm-up and cooldown penalty controls.
- O(1) update/claim accounting (no all-user loops).

## Residual Risks

- Admin key misuse risk.
- Address-level sybil splitting remains possible.
- Integrator misuse of `hookData` LP attribution can degrade fairness.

## Reporting

Open a private security report through your preferred disclosure channel before public issue filing.
