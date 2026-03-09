# Incentive Model

## Weighting Model

The implementation uses a deterministic liquidity-time share model with warm-up and cooldown controls.

### Units

- `weight`: liquidity units attributed to an LP.
- `accRewardPerWeightX18`: cumulative rewards per unit weight (scaled by `1e18`).
- `emissionRate`: reward tokens per second.

### Core Equations

1. Program sync:

`rewards = min((to - from) * emissionRate, fundedBalance)`

2. Global accumulator update:

`accRewardPerWeightX18 += rewards * 1e18 / totalActiveWeight`

3. User accrual:

`pendingRewards += activeWeight * accRewardPerWeightX18 / 1e18 - rewardDebtX18`

## Distribution Modes

- `STREAMING`: no end window required (`endTime = 0`).
- `EPOCH`: rewards accrue only inside `[startTime, endTime]`; epoch rollover is explicit.

## Anti-Manipulation Controls

- Warm-up gate (`pendingWeight` + activation timestamp).
- Cooldown penalty (`earlyWithdrawalPenaltyBps`) for fast exit behavior.
- No loops over all LPs; all claims are O(1).

## Limitations

- LP identity is passed in hook data (`abi.encode(lpAddress)`) for deterministic attribution.
- Sybil splitting remains possible at address-level and is documented as residual risk.
