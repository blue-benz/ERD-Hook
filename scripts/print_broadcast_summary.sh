#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <script-file> <chain-id> [explorer-base-url]" >&2
  exit 1
fi

SCRIPT_FILE="$1"
CHAIN_ID="$2"
EXPLORER_BASE="${3:-TBD}"
JSON_PATH="broadcast/${SCRIPT_FILE}/${CHAIN_ID}/run-latest.json"

if [[ ! -f "$JSON_PATH" ]]; then
  echo "broadcast summary: missing ${JSON_PATH}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "broadcast summary: jq is required" >&2
  exit 1
fi

echo "== Broadcast Summary (${SCRIPT_FILE} / chain ${CHAIN_ID}) =="
cat "$JSON_PATH" | jq -r '.transactions[] | [.transactionType, .contractName, .hash] | @tsv' | while IFS=$'\t' read -r txType contract hash; do
  if [[ "$EXPLORER_BASE" == "TBD" ]]; then
    url="TBD (chain-specific) ${hash}"
  else
    url="${EXPLORER_BASE}/${hash}"
  fi
  printf '%s\t%s\t%s\n' "$txType" "$contract" "$url"
done
