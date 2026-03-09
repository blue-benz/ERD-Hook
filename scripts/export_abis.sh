#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p shared/abi shared/types

forge build >/dev/null

for contract in IncentiveController IncentivesHook RevenueRouter RewardsVault MockRevenueAdapter MockRewardToken; do
  jq '.abi' "out/${contract}.sol/${contract}.json" > "shared/abi/${contract}.json"
done

cat > shared/types/contracts.ts <<'TYPES'
export type Hex = `0x${string}`;

export type DistributionType = 0 | 1;

export interface ProgramConfig {
  rewardToken: Hex;
  distributionType: DistributionType;
  startTime: number;
  endTime: number;
  warmupPeriod: number;
  cooldownPeriod: number;
  earlyWithdrawalPenaltyBps: number;
  emissionRate: bigint;
  maxFunding: bigint;
}

export interface PoolKeyInput {
  currency0: Hex;
  currency1: Hex;
  fee: number;
  tickSpacing: number;
  hooks: Hex;
}
TYPES

echo "[export_abis] exported contract ABIs to shared/abi"
