// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {IRewardsVault} from "./interfaces/IRewardsVault.sol";
import {IIncentiveController} from "./interfaces/IIncentiveController.sol";
import {Owned} from "./utils/Owned.sol";

contract IncentiveController is IIncentiveController, Owned {
    using PoolIdLibrary for PoolKey;

    error NotHook();
    error HookNotConfigured();
    error InvalidHookForPool();
    error ProgramAlreadyExists();
    error ProgramMissing();
    error UpdateNotQueued();
    error UpdateDelayNotMet();

    event HookSet(address indexed previousHook, address indexed newHook);
    event RouterSet(address indexed previousRouter, address indexed newRouter);
    event ProgramCreated(bytes32 indexed poolId, address indexed rewardToken, IRewardsVault.DistributionType distributionType);
    event ProgramUpdateQueued(bytes32 indexed poolId, uint40 executableAt);
    event ProgramUpdateExecuted(bytes32 indexed poolId);
    event SwapObserved(bytes32 indexed poolId, uint256 amountSpecifiedAbs, uint256 cumulativeVolume, uint256 cumulativeCount);

    address public hook;
    address public revenueRouter;
    uint40 public immutable minUpdateDelay;

    IRewardsVault public immutable rewardsVault;

    mapping(bytes32 poolId => bool exists) public programExists;
    mapping(bytes32 poolId => IRewardsVault.ProgramConfig config) private _programConfigs;

    mapping(bytes32 poolId => uint256 volume) public observedSwapVolume;
    mapping(bytes32 poolId => uint256 count) public observedSwapCount;

    struct PendingUpdate {
        bool exists;
        uint40 executableAt;
        IRewardsVault.ProgramConfig config;
    }

    mapping(bytes32 poolId => PendingUpdate update) private _pendingUpdates;

    modifier onlyHook() {
        if (msg.sender != hook) revert NotHook();
        _;
    }

    constructor(address initialOwner, IRewardsVault rewardsVault_, uint40 minUpdateDelaySeconds) Owned(initialOwner) {
        rewardsVault = rewardsVault_;
        minUpdateDelay = minUpdateDelaySeconds;
    }

    function setHook(address newHook) external onlyOwner {
        emit HookSet(hook, newHook);
        hook = newHook;
    }

    function setRevenueRouter(address newRevenueRouter) external onlyOwner {
        emit RouterSet(revenueRouter, newRevenueRouter);
        revenueRouter = newRevenueRouter;
        rewardsVault.setRouter(newRevenueRouter);
    }

    function createProgram(PoolKey calldata key, IRewardsVault.ProgramConfig calldata config) external onlyOwner {
        if (hook == address(0)) revert HookNotConfigured();
        if (address(key.hooks) != hook) revert InvalidHookForPool();

        bytes32 poolId = PoolId.unwrap(key.toId());
        if (programExists[poolId]) revert ProgramAlreadyExists();

        programExists[poolId] = true;
        _programConfigs[poolId] = config;

        rewardsVault.registerProgram(poolId, config);

        emit ProgramCreated(poolId, config.rewardToken, config.distributionType);
    }

    function queueProgramUpdate(bytes32 poolId, IRewardsVault.ProgramConfig calldata config) external onlyOwner {
        if (!programExists[poolId]) revert ProgramMissing();

        PendingUpdate storage pending = _pendingUpdates[poolId];
        pending.exists = true;
        pending.executableAt = uint40(block.timestamp) + minUpdateDelay;
        pending.config = config;

        emit ProgramUpdateQueued(poolId, pending.executableAt);
    }

    function executeProgramUpdate(bytes32 poolId) external onlyOwner {
        PendingUpdate storage pending = _pendingUpdates[poolId];
        if (!pending.exists) revert UpdateNotQueued();
        if (block.timestamp < pending.executableAt) revert UpdateDelayNotMet();

        IRewardsVault.ProgramConfig memory config = pending.config;

        _programConfigs[poolId] = config;
        rewardsVault.updateProgramConfig(poolId, config);

        delete _pendingUpdates[poolId];

        emit ProgramUpdateExecuted(poolId);
    }

    function rollEpoch(bytes32 poolId, uint40 startTime, uint40 endTime, uint96 emissionRate) external onlyOwner {
        rewardsVault.rollEpoch(poolId, startTime, endTime, emissionRate);

        IRewardsVault.ProgramConfig memory config = _programConfigs[poolId];
        config.startTime = startTime;
        config.endTime = endTime;
        config.emissionRate = emissionRate;
        _programConfigs[poolId] = config;
    }

    function claim(bytes32 poolId, address to) external returns (uint256) {
        return rewardsVault.claim(poolId, msg.sender, to);
    }

    function onLiquidityChanged(bytes32 poolId, address lp, int256 liquidityDelta) external onlyHook {
        rewardsVault.onLiquidityDelta(poolId, lp, liquidityDelta);
    }

    function onSwapObserved(bytes32 poolId, uint256 amountSpecifiedAbs) external onlyHook {
        observedSwapVolume[poolId] += amountSpecifiedAbs;
        observedSwapCount[poolId] += 1;

        emit SwapObserved(
            poolId,
            amountSpecifiedAbs,
            observedSwapVolume[poolId],
            observedSwapCount[poolId]
        );
    }

    function rewardToken(bytes32 poolId) external view returns (address) {
        return _programConfigs[poolId].rewardToken;
    }

    function getProgramConfig(bytes32 poolId) external view returns (IRewardsVault.ProgramConfig memory) {
        return _programConfigs[poolId];
    }

    function getPendingUpdate(bytes32 poolId) external view returns (PendingUpdate memory) {
        return _pendingUpdates[poolId];
    }
}
