# Contributing

## Development Setup

1. `make bootstrap`
2. `make build`
3. `make test`
4. `npm install && npm run abi:export && npm run abi:sync`

## Standards

- Keep Solidity and frontend dependency changes deterministic.
- Add or update tests for every behavioral change.
- Keep shared ABIs in `shared/abi` synchronized with contracts.
- Use clear commit messages with conventional prefixes (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).

## Required Checks

- `make test`
- `make coverage`
- Frontend typecheck: `npm run lint --workspace frontend`
