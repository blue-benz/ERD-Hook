#!/usr/bin/env bash
set -euo pipefail

export RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
export CHAIN_ID="${CHAIN_ID:-31337}"

./scripts/demo-streaming.sh
./scripts/demo-epoch.sh
