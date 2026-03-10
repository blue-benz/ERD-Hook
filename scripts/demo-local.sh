#!/usr/bin/env bash
set -euo pipefail

CHAIN_ID=31337
BASE_PORT="${LOCAL_DEMO_BASE_PORT:-8551}"
EXPLORER_TX_BASE="${EXPLORER_TX_BASE:-TBD}"

run_mode() {
  local mode="$1"
  local script_path="$2"
  local port="$3"
  local log_file="/tmp/erd-anvil-${mode}.log"
  local mode_title
  mode_title="$(printf '%s' "$mode" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"

  echo ""
  echo "== Local ${mode_title} Demo =="
  echo "starting isolated anvil node on port ${port} (block-time=1s)"

  anvil --host 127.0.0.1 --port "${port}" --block-time 1 >"${log_file}" 2>&1 &
  local anvil_pid=$!

  cleanup() {
    if kill -0 "${anvil_pid}" >/dev/null 2>&1; then
      kill "${anvil_pid}" >/dev/null 2>&1 || true
      wait "${anvil_pid}" 2>/dev/null || true
    fi
  }
  trap cleanup EXIT

  for _ in $(seq 1 30); do
    if cast chain-id --rpc-url "http://127.0.0.1:${port}" >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done

  RPC_URL="http://127.0.0.1:${port}" \
  CHAIN_ID="${CHAIN_ID}" \
  EXPLORER_TX_BASE="${EXPLORER_TX_BASE}" \
    "${script_path}"

  cleanup
  trap - EXIT
}

echo "== Local Demo All Modes =="
echo "user perspective:"
echo "1) sponsor/protocol funds incentives"
echo "2) LP A joins first, LP B joins later"
echo "3) swap activity occurs"
echo "4) rewards are claimed deterministically"

run_mode "streaming" "./scripts/demo-streaming.sh" "${BASE_PORT}"
run_mode "epoch" "./scripts/demo-epoch.sh" "$((BASE_PORT + 1))"
