#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <script-file> <chain-id> [explorer-base-url] [rpc-url]" >&2
  exit 1
fi

SCRIPT_FILE="$1"
CHAIN_ID="$2"
EXPLORER_BASE="${3:-TBD}"
RPC_URL="${4:-${RPC_URL:-}}"
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
printf '%s\n' "idx	type	contract	contractAddress	txUrl"
cat "$JSON_PATH" | jq -r '.transactions | to_entries[] | [(.key + 1), (.value.transactionType // "CALL"), (.value.contractName // "-"), (.value.contractAddress // "-"), (.value.hash // "-")] | @tsv' | while IFS=$'\t' read -r idx txType contract contractAddress hash; do
  if [[ "$EXPLORER_BASE" == "TBD" ]]; then
    url="TBD (chain-specific) ${hash}"
  else
    url="${EXPLORER_BASE}/${hash}"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$idx" "$txType" "$contract" "$contractAddress" "$url"
done

if [[ -n "$RPC_URL" ]] && command -v cast >/dev/null 2>&1; then
  CLAIM_EVENT_SIG="$(cast keccak "RewardsClaimed(bytes32,address,address,uint256)")"
  CLAIM_HASHES="$(jq -r '.transactions[] | select(.function == "claim(bytes32,address)") | .hash' "$JSON_PATH")"

  if [[ -n "$CLAIM_HASHES" ]]; then
    echo ""
    echo "== Claim Event Summary =="
    printf '%s\n' "txHash	lp	to	amount	txUrl"
    while IFS= read -r hash; do
      [[ -z "$hash" ]] && continue

      receipt="$(cast receipt "$hash" --rpc-url "$RPC_URL" --json)"
      matchCount="$(echo "$receipt" | jq --arg sig "$CLAIM_EVENT_SIG" '[.logs[] | select(.topics[0] == $sig)] | length')"
      if [[ "$matchCount" == "0" ]]; then
        if [[ "$EXPLORER_BASE" == "TBD" ]]; then
          url="TBD (chain-specific) ${hash}"
        else
          url="${EXPLORER_BASE}/${hash}"
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$hash" "-" "-" "0" "$url"
        continue
      fi

      while IFS=$'\t' read -r lp to amountHex; do
        amount="$(cast to-dec "0x${amountHex}")"
        if [[ "$EXPLORER_BASE" == "TBD" ]]; then
          url="TBD (chain-specific) ${hash}"
        else
          url="${EXPLORER_BASE}/${hash}"
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$hash" "$lp" "$to" "$amount" "$url"
      done < <(
        echo "$receipt" | jq -r --arg sig "$CLAIM_EVENT_SIG" '
          .logs[]
          | select(.topics[0] == $sig)
          | [
              ("0x" + (.topics[2] | ltrimstr("0x") | .[24:])),
              ("0x" + (.topics[3] | ltrimstr("0x") | .[24:])),
              (.data | ltrimstr("0x"))
            ]
          | @tsv
        '
      )
    done <<< "$CLAIM_HASHES"
  fi
fi
