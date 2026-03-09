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

Use `make demo-all` to run both distribution modes sequentially.
