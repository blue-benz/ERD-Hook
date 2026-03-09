# Testing

## Suites

- `test/IncentivesSystem.t.sol`: end-to-end hook/controller/router/vault integration.
- `test/EpochDistribution.t.sol`: epoch behavior and rollover.
- `test/RewardsVaultEdge.t.sol`: edge-case and authorization tests.
- `test/fuzz/RewardsVaultFuzz.t.sol`: accounting and warm-up invariants.

## Commands

```bash
make test
make coverage
```

## Required Invariants Covered

- `totalClaimed <= totalFunded`
- `totalDistributed <= totalFunded`
- claim idempotency (second claim returns zero)
- warm-up behavior under fuzzed timings
