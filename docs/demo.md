# Demo Flow

`make demo-streaming` and `make demo-epoch` execute:

1. Deploy v4 infra (local) and ERD stack.
2. Create pool and initialize hook-linked program.
3. Fund via direct sponsor and mock adapter.
4. LP A provides liquidity.
5. LP B provides liquidity later.
6. Swap executes to show pool activity.
7. LPs claim rewards.
8. Summary logs print funded totals, claims, and anti-gaming signals (`totalSlashed`).
9. `scripts/print_broadcast_summary.sh` prints every tx hash and an on-chain `Claim Event Summary` decoded from receipts.

Use `make demo-all` to run both distribution modes sequentially.

Use `make demo-local` for the most reliable local judge run. It starts isolated anvil nodes per mode (`--block-time 1`), avoiding CREATE2 collisions between runs and producing deterministic accrual windows.
