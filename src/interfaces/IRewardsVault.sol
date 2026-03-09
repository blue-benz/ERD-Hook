// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IRewardsVault {
    enum DistributionType {
        STREAMING,
        EPOCH
    }

    struct ProgramConfig {
        address rewardToken;
        DistributionType distributionType;
        uint40 startTime;
        uint40 endTime;
        uint40 warmupPeriod;
        uint40 cooldownPeriod;
        uint16 earlyWithdrawalPenaltyBps;
        uint96 emissionRate;
        uint256 maxFunding;
    }

    struct ProgramState {
        bool exists;
        address rewardToken;
        DistributionType distributionType;
        uint40 startTime;
        uint40 endTime;
        uint40 warmupPeriod;
        uint40 cooldownPeriod;
        uint16 earlyWithdrawalPenaltyBps;
        uint96 emissionRate;
        uint40 lastUpdate;
        uint256 accRewardPerWeightX18;
        uint256 fundedBalance;
        uint256 totalFunded;
        uint256 totalActiveWeight;
        uint256 totalPendingWeight;
        uint256 totalDistributed;
        uint256 totalClaimed;
        uint256 totalSlashed;
    }

    struct UserState {
        uint256 activeWeight;
        uint256 pendingWeight;
        uint40 pendingActivation;
        uint40 lastStakeIncrease;
        uint256 rewardDebtX18;
        uint256 pendingRewards;
    }

    function setRouter(address newRouter) external;
    function registerProgram(bytes32 poolId, ProgramConfig calldata config) external;
    function updateProgramConfig(bytes32 poolId, ProgramConfig calldata config) external;
    function fundProgram(bytes32 poolId, uint256 amount, address source) external;
    function onLiquidityDelta(bytes32 poolId, address lp, int256 liquidityDelta) external;
    function rollEpoch(bytes32 poolId, uint40 startTime, uint40 endTime, uint96 emissionRate) external;
    function claim(bytes32 poolId, address lp, address to) external returns (uint256 amountOut);
    function claimable(bytes32 poolId, address lp) external view returns (uint256 amountOut);
    function getProgramState(bytes32 poolId) external view returns (ProgramState memory);
    function getUserState(bytes32 poolId, address lp) external view returns (UserState memory);
}
