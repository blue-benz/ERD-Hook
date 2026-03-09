#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PINNED_PERIPHERY_COMMIT="3779387e5d296f39df543d23524b050f89a62917"
PINNED_PERIPHERY_SHORT="3779387"

V4_PERIPHERY_DIR="lib/uniswap-hooks/lib/v4-periphery"
V4_CORE_DIR="lib/uniswap-hooks/lib/v4-core"

echo "[bootstrap] syncing submodules"
git submodule sync --recursive
git submodule update --init --recursive

echo "[bootstrap] pinning v4-periphery to ${PINNED_PERIPHERY_SHORT}"
git -C "$V4_PERIPHERY_DIR" fetch --tags --prune origin
git -C "$V4_PERIPHERY_DIR" checkout "$PINNED_PERIPHERY_COMMIT"
git -C "$V4_PERIPHERY_DIR" submodule update --init --recursive

CURRENT_PERIPHERY_SHORT="$(git -C "$V4_PERIPHERY_DIR" rev-parse --short=7 HEAD)"
if [[ "$CURRENT_PERIPHERY_SHORT" != "$PINNED_PERIPHERY_SHORT" ]]; then
  echo "[bootstrap] ERROR: expected v4-periphery ${PINNED_PERIPHERY_SHORT}, got ${CURRENT_PERIPHERY_SHORT}" >&2
  exit 1
fi

echo "[bootstrap] aligning root v4-core to v4-periphery's submodule pin"
CORE_SUBMODULE_SHA="$(git -C "$V4_PERIPHERY_DIR" submodule status lib/v4-core | awk '{print $1}' | sed 's/^[+-]//')"
git -C "$V4_CORE_DIR" fetch --tags --prune origin
if ! git -C "$V4_CORE_DIR" cat-file -e "${CORE_SUBMODULE_SHA}^{commit}"; then
  git -C "$V4_CORE_DIR" fetch origin "$CORE_SUBMODULE_SHA"
fi
git -C "$V4_CORE_DIR" checkout "$CORE_SUBMODULE_SHA"
git -C "$V4_CORE_DIR" submodule update --init --recursive

CURRENT_CORE_SHA="$(git -C "$V4_CORE_DIR" rev-parse HEAD)"
if [[ "$CURRENT_CORE_SHA" != "$CORE_SUBMODULE_SHA" ]]; then
  echo "[bootstrap] ERROR: expected v4-core ${CORE_SUBMODULE_SHA}, got ${CURRENT_CORE_SHA}" >&2
  exit 1
fi

echo "[bootstrap] done"
echo "[bootstrap] v4-periphery=${CURRENT_PERIPHERY_SHORT}"
echo "[bootstrap] v4-core=$(git -C "$V4_CORE_DIR" rev-parse --short=8 HEAD)"
