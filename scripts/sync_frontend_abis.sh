#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p frontend/src/abi
cp shared/abi/*.json frontend/src/abi/

echo "[sync_frontend_abis] copied ABIs into frontend/src/abi"
