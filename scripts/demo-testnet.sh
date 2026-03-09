#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${RPC_URL:-}" ]]; then
  echo "RPC_URL is required for testnet demo" >&2
  exit 1
fi

CHAIN_ID="${CHAIN_ID:-84532}" # Base Sepolia default
MODE="${MODE:-streaming}"

if [[ "$MODE" == "streaming" ]]; then
  forge script script/10_DemoStreaming.s.sol:DemoStreamingScript --rpc-url "$RPC_URL" --broadcast -vvv
  ./scripts/print_broadcast_summary.sh 10_DemoStreaming.s.sol "$CHAIN_ID" "${EXPLORER_TX_BASE:-TBD}"
else
  forge script script/11_DemoEpoch.s.sol:DemoEpochScript --rpc-url "$RPC_URL" --broadcast -vvv
  ./scripts/print_broadcast_summary.sh 11_DemoEpoch.s.sol "$CHAIN_ID" "${EXPLORER_TX_BASE:-TBD}"
fi
