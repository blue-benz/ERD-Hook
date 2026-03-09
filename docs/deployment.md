# Deployment

## Prerequisites

- Foundry
- `jq`
- RPC endpoint and funded deployer key

## Bootstrap

```bash
make bootstrap
```

This initializes submodules and enforces the pinned Uniswap v4 periphery commit (`3779387`).

## Local

```bash
anvil
make demo-local
```

## Base Sepolia (preferred)

```bash
cp .env.example .env
# set PRIVATE_KEY, LP_A_PRIVATE_KEY, LP_B_PRIVATE_KEY, RPC_URL, CHAIN_ID=84532
source .env
MODE=streaming make demo-testnet
MODE=epoch make demo-testnet
```

## Address / Tx Output

- Deployment and tx traces are written under `broadcast/`.
- Run `scripts/print_broadcast_summary.sh` to print hashes and explorer URLs.
- If explorer base is unknown, output uses `TBD (chain-specific)` with raw hashes.
