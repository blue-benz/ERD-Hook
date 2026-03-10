#!/usr/bin/env bash
set -euo pipefail

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

RPC_URL="${RPC_URL:-${SEPOLIA_RPC_URL:-${unichain_SEPOLIA_RPC_URL:-}}}"
CHAIN_ID="${CHAIN_ID:-${SEPOLIA_CHAIN_ID:-1301}}" # Unichain Sepolia default
EXPLORER_TX_BASE="${EXPLORER_TX_BASE:-https://sepolia.uniscan.xyz/tx}"
MODE="${MODE:-streaming}"
TESTNET_DEPLOY_ONLY="${TESTNET_DEPLOY_ONLY:-true}"
export TESTNET_DEPLOY_ONLY

if [[ -z "${RPC_URL}" ]]; then
  echo "RPC_URL is required for testnet demo" >&2
  exit 1
fi

echo "== Demo Testnet Runner =="
echo "chain_id=${CHAIN_ID}"
echo "mode=${MODE}"
echo "rpc_url=${RPC_URL}"
echo "explorer_tx_base=${EXPLORER_TX_BASE}"
echo "phase 0: preflight"
echo "phase 1: deploy + configure + fund"
echo "phase 2: LP A enters, LP B enters later"
echo "phase 3: swap activity + claims + fairness summary"

if [[ "$TESTNET_DEPLOY_ONLY" == "true" ]]; then
  echo "deploy-only mode enabled for testnet stability (set TESTNET_DEPLOY_ONLY=false to run full lifecycle)"
elif [[ -n "${PRIVATE_KEY:-}" && -n "${LP_A_PRIVATE_KEY:-}" && -n "${LP_B_PRIVATE_KEY:-}" ]]; then
  LP_TARGET_WEI=20000000000000000 # 0.02 native token
  FUNDER_ADDR=$(cast wallet address --private-key "$PRIVATE_KEY")
  LP_A_ADDR=$(cast wallet address --private-key "$LP_A_PRIVATE_KEY")
  LP_B_ADDR=$(cast wallet address --private-key "$LP_B_PRIVATE_KEY")

  LP_A_BAL=$(cast balance "$LP_A_ADDR" --rpc-url "$RPC_URL")
  LP_B_BAL=$(cast balance "$LP_B_ADDR" --rpc-url "$RPC_URL")

  if (( LP_A_BAL < LP_TARGET_WEI )); then
    NONCE=$(cast nonce "$FUNDER_ADDR" --rpc-url "$RPC_URL" --block pending)
    cast send "$LP_A_ADDR" --value "$LP_TARGET_WEI" --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" --nonce "$NONCE" >/dev/null
    echo "prefunded lpA=$LP_A_ADDR wei=$LP_TARGET_WEI"
  fi

  if (( LP_B_BAL < LP_TARGET_WEI )); then
    NONCE=$(cast nonce "$FUNDER_ADDR" --rpc-url "$RPC_URL" --block pending)
    cast send "$LP_B_ADDR" --value "$LP_TARGET_WEI" --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" --nonce "$NONCE" >/dev/null
    echo "prefunded lpB=$LP_B_ADDR wei=$LP_TARGET_WEI"
  fi
else
  echo "warning: PRIVATE_KEY / LP_A_PRIVATE_KEY / LP_B_PRIVATE_KEY missing, skipping LP prefund"
fi

if [[ "$MODE" == "streaming" ]]; then
  forge script script/10_DemoStreaming.s.sol:DemoStreamingScript \
    --rpc-url "$RPC_URL" \
    --broadcast \
    --slow \
    --gas-estimate-multiplier 500 \
    -vvv
  ./scripts/print_broadcast_summary.sh 10_DemoStreaming.s.sol "$CHAIN_ID" "$EXPLORER_TX_BASE" "$RPC_URL"
else
  forge script script/11_DemoEpoch.s.sol:DemoEpochScript \
    --rpc-url "$RPC_URL" \
    --broadcast \
    --slow \
    --gas-estimate-multiplier 500 \
    -vvv
  ./scripts/print_broadcast_summary.sh 11_DemoEpoch.s.sol "$CHAIN_ID" "$EXPLORER_TX_BASE" "$RPC_URL"
fi
