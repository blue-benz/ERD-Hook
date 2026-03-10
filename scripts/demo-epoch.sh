#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
CHAIN_ID="${CHAIN_ID:-31337}"

echo "== Epoch Demo =="
echo "chain_id=${CHAIN_ID}"
echo "phase 1: deploy + configure epoch program"
echo "phase 2: direct + adapter funding across epoch"
echo "phase 3: LP A first, LP B later, swap activity"
echo "phase 4: epoch rollover + claims + fairness summary"

forge script script/11_DemoEpoch.s.sol:DemoEpochScript \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --gas-estimate-multiplier 500 \
  -vvv

./scripts/print_broadcast_summary.sh 11_DemoEpoch.s.sol "$CHAIN_ID" "${EXPLORER_TX_BASE:-TBD}" "$RPC_URL"
