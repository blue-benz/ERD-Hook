// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IRewardsVault} from "./interfaces/IRewardsVault.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {WeightingLibrary} from "./libraries/WeightingLibrary.sol";
import {Owned} from "./utils/Owned.sol";
import {ReentrancyLock} from "./utils/ReentrancyLock.sol";

contract RewardsVault is IRewardsVault, Owned, ReentrancyLock {
    using WeightingLibrary for int256;

    error NotController();
    error NotRouter();
    error ControllerAlreadySet();
    error ProgramExists();
    error ProgramNotFound();
    error InvalidConfig();
    error RewardTokenImmutable();
    error FundingCapExceeded();
    error InvalidLiquidityDelta();
    error InsufficientWeight();
    error InvalidEpochWindow();
    error UnauthorizedClaim();

    event ControllerUpdated(address indexed previousController, address indexed newController);
    event RouterUpdated(address indexed previousRouter, address indexed newRouter);
    event ProgramRegistered(bytes32 indexed poolId, address indexed rewardToken, DistributionType distributionType);
    event ProgramUpdated(bytes32 indexed poolId, uint96 emissionRate, uint40 startTime, uint40 endTime);
    event ProgramFunded(bytes32 indexed poolId, address indexed source, uint256 amount);
    event LiquidityWeightUpdated(
        bytes32 indexed poolId,
        address indexed lp,
        int256 liquidityDelta,
        uint256 activeWeight,
        uint256 pendingWeight
    );
    event RewardsClaimed(bytes32 indexed poolId, address indexed lp, address indexed to, uint256 amount);
    event EpochRolled(bytes32 indexed poolId, uint40 startTime, uint40 endTime, uint96 emissionRate);

    address public controller;
    address public router;

    struct ProgramInternal {
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
        uint256 maxFunding;
    }

    mapping(bytes32 poolId => ProgramInternal program) private _programs;
    mapping(bytes32 poolId => mapping(address lp => UserState state)) private _users;

    modifier onlyController() {
        if (msg.sender != controller) revert NotController();
        _;
    }

    modifier onlyRouter() {
        if (msg.sender != router) revert NotRouter();
        _;
    }

    constructor(address initialOwner) Owned(initialOwner) {}

    function setController(address newController) external onlyOwner {
        if (newController == address(0)) revert InvalidConfig();
        if (controller != address(0)) revert ControllerAlreadySet();
        emit ControllerUpdated(controller, newController);
        controller = newController;
    }

    function setRouter(address newRouter) external onlyController {
        emit RouterUpdated(router, newRouter);
        router = newRouter;
    }

    function registerProgram(bytes32 poolId, ProgramConfig calldata config) external onlyController {
        if (_programs[poolId].exists) revert ProgramExists();
        _validateConfig(config);

        uint40 normalizedStart = config.startTime == 0 ? uint40(block.timestamp) : config.startTime;

        _programs[poolId] = ProgramInternal({
            exists: true,
            rewardToken: config.rewardToken,
            distributionType: config.distributionType,
            startTime: normalizedStart,
            endTime: config.endTime,
            warmupPeriod: config.warmupPeriod,
            cooldownPeriod: config.cooldownPeriod,
            earlyWithdrawalPenaltyBps: config.earlyWithdrawalPenaltyBps,
            emissionRate: config.emissionRate,
            lastUpdate: uint40(block.timestamp),
            accRewardPerWeightX18: 0,
            fundedBalance: 0,
            totalFunded: 0,
            totalActiveWeight: 0,
            totalPendingWeight: 0,
            totalDistributed: 0,
            totalClaimed: 0,
            totalSlashed: 0,
            maxFunding: config.maxFunding
        });

        emit ProgramRegistered(poolId, config.rewardToken, config.distributionType);
    }

    function updateProgramConfig(bytes32 poolId, ProgramConfig calldata config) external onlyController {
        ProgramInternal storage program = _programs[poolId];
        if (!program.exists) revert ProgramNotFound();
        _validateConfig(config);

        if (config.rewardToken != program.rewardToken) revert RewardTokenImmutable();

        _syncProgram(program);

        program.distributionType = config.distributionType;
        program.startTime = config.startTime == 0 ? uint40(block.timestamp) : config.startTime;
        program.endTime = config.endTime;
        program.warmupPeriod = config.warmupPeriod;
        program.cooldownPeriod = config.cooldownPeriod;
        program.earlyWithdrawalPenaltyBps = config.earlyWithdrawalPenaltyBps;
        program.emissionRate = config.emissionRate;
        program.maxFunding = config.maxFunding;

        emit ProgramUpdated(poolId, config.emissionRate, program.startTime, config.endTime);
    }

    function fundProgram(bytes32 poolId, uint256 amount, address source) external onlyRouter {
        ProgramInternal storage program = _programs[poolId];
        if (!program.exists) revert ProgramNotFound();

        _syncProgram(program);

        if (program.maxFunding != 0 && program.totalFunded + amount > program.maxFunding) revert FundingCapExceeded();

        program.totalFunded += amount;
        program.fundedBalance += amount;

        emit ProgramFunded(poolId, source, amount);
    }

    function onLiquidityDelta(bytes32 poolId, address lp, int256 liquidityDelta) external onlyController {
        if (liquidityDelta == 0) revert InvalidLiquidityDelta();

        ProgramInternal storage program = _programs[poolId];
        if (!program.exists) revert ProgramNotFound();

        UserState storage user = _users[poolId][lp];

        _syncProgram(program);
        _activatePending(program, user);
        _settle(program, user);

        if (liquidityDelta > 0) {
            uint256 added = uint256(liquidityDelta);
            user.pendingWeight += added;
            program.totalPendingWeight += added;
            user.pendingActivation =
                WeightingLibrary.mergeActivation(user.pendingActivation, uint40(block.timestamp) + program.warmupPeriod);
            user.lastStakeIncrease = uint40(block.timestamp);
        } else {
            uint256 toRemove = liquidityDelta.abs();

            uint256 fromPending = toRemove > user.pendingWeight ? user.pendingWeight : toRemove;
            if (fromPending > 0) {
                user.pendingWeight -= fromPending;
                program.totalPendingWeight -= fromPending;
                toRemove -= fromPending;
                if (user.pendingWeight == 0) user.pendingActivation = 0;
            }

            if (toRemove > 0) {
                if (toRemove > user.activeWeight) revert InsufficientWeight();
                user.activeWeight -= toRemove;
                program.totalActiveWeight -= toRemove;

                if (
                    program.cooldownPeriod > 0
                        && block.timestamp < uint256(user.lastStakeIncrease) + uint256(program.cooldownPeriod)
                ) {
                    (uint256 netRewards, uint256 penaltyRewards) =
                        WeightingLibrary.applyPenalty(user.pendingRewards, program.earlyWithdrawalPenaltyBps);
                    if (penaltyRewards > 0) {
                        user.pendingRewards = netRewards;
                        program.fundedBalance += penaltyRewards;
                        program.totalSlashed += penaltyRewards;
                    }
                }
            }
        }

        _updateRewardDebt(program, user);

        emit LiquidityWeightUpdated(poolId, lp, liquidityDelta, user.activeWeight, user.pendingWeight);
    }

    function rollEpoch(bytes32 poolId, uint40 startTime, uint40 endTime, uint96 emissionRate) external onlyController {
        if (endTime <= startTime) revert InvalidEpochWindow();

        ProgramInternal storage program = _programs[poolId];
        if (!program.exists) revert ProgramNotFound();
        if (program.distributionType != DistributionType.EPOCH) revert InvalidConfig();

        _syncProgram(program);

        program.startTime = startTime;
        program.endTime = endTime;
        program.emissionRate = emissionRate;

        emit EpochRolled(poolId, startTime, endTime, emissionRate);
    }

    function claim(bytes32 poolId, address lp, address to)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (msg.sender != lp && msg.sender != controller) revert UnauthorizedClaim();

        ProgramInternal storage program = _programs[poolId];
        if (!program.exists) revert ProgramNotFound();

        UserState storage user = _users[poolId][lp];

        _syncProgram(program);
        _activatePending(program, user);
        _settle(program, user);
        _updateRewardDebt(program, user);

        amountOut = user.pendingRewards;
        if (amountOut == 0) return 0;

        user.pendingRewards = 0;
        program.totalClaimed += amountOut;

        address recipient = to == address(0) ? lp : to;
        TransferHelper.safeTransfer(program.rewardToken, recipient, amountOut);

        emit RewardsClaimed(poolId, lp, recipient, amountOut);
    }

    function claimable(bytes32 poolId, address lp) external view returns (uint256 amountOut) {
        ProgramInternal memory program = _programs[poolId];
        if (!program.exists) return 0;

        UserState memory user = _users[poolId][lp];

        uint256 previewAcc = _previewAcc(program);

        if (user.pendingWeight > 0 && block.timestamp >= user.pendingActivation) {
            user.activeWeight += user.pendingWeight;
            user.pendingWeight = 0;
        }

        amountOut = user.pendingRewards;
        if (user.activeWeight == 0) return amountOut;

        uint256 cumulative = (user.activeWeight * previewAcc) / WeightingLibrary.ACC_PRECISION;
        if (cumulative > user.rewardDebtX18) {
            amountOut += cumulative - user.rewardDebtX18;
        }
    }

    function getProgramState(bytes32 poolId) external view returns (ProgramState memory) {
        ProgramInternal memory p = _programs[poolId];
        return ProgramState({
            exists: p.exists,
            rewardToken: p.rewardToken,
            distributionType: p.distributionType,
            startTime: p.startTime,
            endTime: p.endTime,
            warmupPeriod: p.warmupPeriod,
            cooldownPeriod: p.cooldownPeriod,
            earlyWithdrawalPenaltyBps: p.earlyWithdrawalPenaltyBps,
            emissionRate: p.emissionRate,
            lastUpdate: p.lastUpdate,
            accRewardPerWeightX18: p.accRewardPerWeightX18,
            fundedBalance: p.fundedBalance,
            totalFunded: p.totalFunded,
            totalActiveWeight: p.totalActiveWeight,
            totalPendingWeight: p.totalPendingWeight,
            totalDistributed: p.totalDistributed,
            totalClaimed: p.totalClaimed,
            totalSlashed: p.totalSlashed
        });
    }

    function getUserState(bytes32 poolId, address lp) external view returns (UserState memory) {
        return _users[poolId][lp];
    }

    function _validateConfig(ProgramConfig calldata config) internal pure {
        if (config.rewardToken == address(0)) revert InvalidConfig();
        if (config.earlyWithdrawalPenaltyBps > uint16(WeightingLibrary.BPS_DENOMINATOR)) revert InvalidConfig();
        if (config.distributionType == DistributionType.EPOCH && config.endTime <= config.startTime) {
            revert InvalidConfig();
        }
    }

    function _activatePending(ProgramInternal storage program, UserState storage user) internal {
        if (user.pendingWeight == 0 || block.timestamp < user.pendingActivation) return;

        uint256 activated = user.pendingWeight;
        uint256 activationDebt = (activated * program.accRewardPerWeightX18) / WeightingLibrary.ACC_PRECISION;

        user.pendingWeight = 0;
        user.pendingActivation = 0;
        user.activeWeight += activated;
        user.rewardDebtX18 += activationDebt;

        program.totalPendingWeight -= activated;
        program.totalActiveWeight += activated;
    }

    function _settle(ProgramInternal storage program, UserState storage user) internal {
        if (user.activeWeight == 0) return;

        uint256 cumulative = (user.activeWeight * program.accRewardPerWeightX18) / WeightingLibrary.ACC_PRECISION;
        if (cumulative > user.rewardDebtX18) {
            user.pendingRewards += cumulative - user.rewardDebtX18;
        }
    }

    function _updateRewardDebt(ProgramInternal storage program, UserState storage user) internal {
        user.rewardDebtX18 = (user.activeWeight * program.accRewardPerWeightX18) / WeightingLibrary.ACC_PRECISION;
    }

    function _syncProgram(ProgramInternal storage program) internal {
        uint40 current = uint40(block.timestamp);
        if (current <= program.lastUpdate) return;

        (uint40 fromTs, uint40 toTs) = _distributionWindow(program, program.lastUpdate, current);

        if (toTs > fromTs && program.totalActiveWeight > 0 && program.fundedBalance > 0) {
            uint256 rewards = uint256(toTs - fromTs) * uint256(program.emissionRate);
            if (rewards > program.fundedBalance) rewards = program.fundedBalance;

            if (rewards > 0) {
                program.fundedBalance -= rewards;
                program.totalDistributed += rewards;
                program.accRewardPerWeightX18 += (rewards * WeightingLibrary.ACC_PRECISION) / program.totalActiveWeight;
            }
        }

        program.lastUpdate = current;
    }

    function _previewAcc(ProgramInternal memory program) internal view returns (uint256) {
        uint40 current = uint40(block.timestamp);
        if (current <= program.lastUpdate) return program.accRewardPerWeightX18;

        (uint40 fromTs, uint40 toTs) = _distributionWindow(program, program.lastUpdate, current);
        if (toTs <= fromTs || program.totalActiveWeight == 0 || program.fundedBalance == 0) {
            return program.accRewardPerWeightX18;
        }

        uint256 rewards = uint256(toTs - fromTs) * uint256(program.emissionRate);
        if (rewards > program.fundedBalance) rewards = program.fundedBalance;

        return program.accRewardPerWeightX18 + (rewards * WeightingLibrary.ACC_PRECISION) / program.totalActiveWeight;
    }

    function _distributionWindow(ProgramInternal memory program, uint40 fromTs, uint40 toTs)
        internal
        pure
        returns (uint40 start, uint40 end)
    {
        start = fromTs > program.startTime ? fromTs : program.startTime;
        end = toTs;

        if (program.endTime != 0 && end > program.endTime) {
            end = program.endTime;
        }

        if (end < start) {
            return (0, 0);
        }
    }
}
