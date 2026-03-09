#!/usr/bin/env bash
set -euo pipefail

EXPECTED="${1:-${COMMIT_TARGET:-}}"
if [[ -z "$EXPECTED" ]]; then
  echo "commit-count-check: SKIP (no expected count provided)"
  exit 0
fi
COUNT="$(git rev-list --count HEAD)"

if [[ "$COUNT" != "$EXPECTED" ]]; then
  echo "commit-count-check: FAIL (expected=${EXPECTED}, actual=${COUNT})"
  exit 1
fi

echo "commit-count-check: PASS (${COUNT})"
