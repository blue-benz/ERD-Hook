# Revenue Routing

## Paths

1. Direct sponsor funding
- Caller transfers reward token through `RevenueRouter.directFund(poolId, amount)`.

2. Adapter funding
- Approved adapter calls `RevenueRouter.adapterFund(poolId, amount)`.
- Demo adapter: `MockRevenueAdapter`.

## Deterministic Constraints

- Reward token is looked up from program config (`controller.rewardToken(poolId)`).
- Funding is rejected for unknown/unconfigured programs.
- Optional funding cap is enforced in `RewardsVault`.
