#!/usr/bin/env bash
set -euo pipefail

EXPECTED="${1:-54}"
COUNT="$(git rev-list --count HEAD)"

if [[ "$COUNT" != "$EXPECTED" ]]; then
  echo "commit-count-check: FAIL (expected=${EXPECTED}, actual=${COUNT})"
  exit 1
fi

echo "commit-count-check: PASS (${COUNT})"
