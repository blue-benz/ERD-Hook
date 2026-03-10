#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
CHAIN_ID="${CHAIN_ID:-31337}"

echo "== Streaming Demo =="
echo "chain_id=${CHAIN_ID}"
echo "phase 1: deploy + configure streaming program"
echo "phase 2: fund via direct sponsor + adapter revenue"
echo "phase 3: LP A first, LP B later, swap activity"
echo "phase 4: claim + fairness summary"

forge script script/10_DemoStreaming.s.sol:DemoStreamingScript \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --gas-estimate-multiplier 500 \
  -vvv

./scripts/print_broadcast_summary.sh 10_DemoStreaming.s.sol "$CHAIN_ID" "${EXPLORER_TX_BASE:-TBD}" "$RPC_URL"
