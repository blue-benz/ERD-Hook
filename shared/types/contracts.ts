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
