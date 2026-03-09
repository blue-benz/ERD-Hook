# Frontend

The frontend (`/frontend`) is an Incentives Console for:

- Program creation from pool key + config.
- Direct funding and mock-adapter funding.
- LP add/remove liquidity calls via PositionManager.
- Reward claiming.
- Fairness readouts (`claimable`, program totals, accumulator state).

## Run

```bash
npm install
npm run abi:export
npm run abi:sync
npm run dev
```

## ABI Source of Truth

- Shared ABIs live in `/shared/abi`.
- Frontend receives copied ABIs via `scripts/sync_frontend_abis.sh`.
