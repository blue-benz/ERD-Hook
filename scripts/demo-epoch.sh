#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
CHAIN_ID="${CHAIN_ID:-31337}"

forge script script/11_DemoEpoch.s.sol:DemoEpochScript \
  --rpc-url "$RPC_URL" \
  --broadcast \
  -vvv

./scripts/print_broadcast_summary.sh 11_DemoEpoch.s.sol "$CHAIN_ID" "${EXPLORER_TX_BASE:-TBD}"
