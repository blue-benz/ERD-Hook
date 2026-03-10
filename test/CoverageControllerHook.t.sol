// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {IncentiveController} from "../src/IncentiveController.sol";
import {IncentivesHook} from "../src/IncentivesHook.sol";
import {RevenueRouter} from "../src/RevenueRouter.sol";
import {RewardsVault} from "../src/RewardsVault.sol";
import {IRewardsVault} from "../src/interfaces/IRewardsVault.sol";
import {ERDTestBase} from "./utils/ERDTestBase.sol";

contract CoverageControllerHookTest is ERDTestBase {
    function _streamingConfig(uint96 emissionRate) internal view returns (IRewardsVault.ProgramConfig memory) {
        return IRewardsVault.ProgramConfig({
            rewardToken: address(rewardToken),
            distributionType: IRewardsVault.DistributionType.STREAMING,
            startTime: uint40(block.timestamp),
            endTime: 0,
            warmupPeriod: 10,
            cooldownPeriod: 1 days,
            earlyWithdrawalPenaltyBps: 500,
            emissionRate: emissionRate,
            maxFunding: type(uint128).max
        });
    }

    function _hookModify(int256 liquidityDelta, bytes memory hookData) internal {
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidityDelta, salt: bytes32(0)});

        if (liquidityDelta >= 0) {
            vm.prank(address(poolManager));
            hook.beforeAddLiquidity(address(this), poolKey, params, hookData);
        } else {
            vm.prank(address(poolManager));
            hook.beforeRemoveLiquidity(address(this), poolKey, params, hookData);
        }
    }

    function testCreateProgramRevertsWhenHookNotConfigured() public {
        RewardsVault localVault = new RewardsVault(address(this));
        IncentiveController localController = new IncentiveController(address(this), IRewardsVault(address(localVault)), 1 hours);
        localVault.setController(address(localController));

        vm.expectRevert(IncentiveController.HookNotConfigured.selector);
        localController.createProgram(poolKey, _streamingConfig(1 ether));
    }

    function testCreateProgramRevertsWhenHookMismatched() public {
        RewardsVault localVault = new RewardsVault(address(this));
        IncentiveController localController = new IncentiveController(address(this), IRewardsVault(address(localVault)), 1 hours);
        localVault.setController(address(localController));
        localController.setHook(address(0xBEEF));

        vm.expectRevert(IncentiveController.InvalidHookForPool.selector);
        localController.createProgram(poolKey, _streamingConfig(1 ether));
    }

    function testCreateProgramRevertsWhenAlreadyExists() public {
        _createStreamingProgram(1 ether, 10, 1 days, 500);

        vm.expectRevert(IncentiveController.ProgramAlreadyExists.selector);
        controller.createProgram(poolKey, _streamingConfig(1 ether));
    }

    function testQueueAndExecuteProgramUpdateLifecycle() public {
        _createStreamingProgram(1 ether, 10, 1 days, 500);

        IRewardsVault.ProgramConfig memory config = _streamingConfig(2 ether);
        config.cooldownPeriod = 3 days;
        controller.queueProgramUpdate(poolId, config);

        IncentiveController.PendingUpdate memory pending = controller.getPendingUpdate(poolId);
        assertTrue(pending.exists);
        assertGt(pending.executableAt, block.timestamp);

        vm.expectRevert(IncentiveController.UpdateDelayNotMet.selector);
        controller.executeProgramUpdate(poolId);

        vm.warp(block.timestamp + controller.minUpdateDelay());
        controller.executeProgramUpdate(poolId);

        IRewardsVault.ProgramConfig memory updated = controller.getProgramConfig(poolId);
        assertEq(updated.emissionRate, 2 ether);
        assertEq(updated.cooldownPeriod, 3 days);

        pending = controller.getPendingUpdate(poolId);
        assertFalse(pending.exists);
    }

    function testExecuteProgramUpdateRevertsWhenNotQueued() public {
        _createStreamingProgram(1 ether, 10, 1 days, 500);

        vm.expectRevert(IncentiveController.UpdateNotQueued.selector);
        controller.executeProgramUpdate(poolId);
    }

    function testQueueProgramUpdateRevertsWhenProgramMissing() public {
        vm.expectRevert(IncentiveController.ProgramMissing.selector);
        controller.queueProgramUpdate(bytes32(uint256(123)), _streamingConfig(1 ether));
    }

    function testOnlyHookMethodsRevertForNonHookCaller() public {
        vm.expectRevert(IncentiveController.NotHook.selector);
        controller.onLiquidityChanged(poolId, ALICE, int256(1));

        vm.expectRevert(IncentiveController.NotHook.selector);
        controller.onSwapObserved(poolId, 1);
    }

    function testBeforeRemoveLiquidityHookPathUpdatesWeights() public {
        _createStreamingProgram(1 ether, 10, 1 days, 500);
        _fundDirect(200 ether);

        _hookModify(int256(80 ether), abi.encode(ALICE));
        vm.warp(block.timestamp + 20);
        _hookModify(int256(1), abi.encode(ALICE));
        _hookModify(-int256(1), abi.encode(ALICE));

        IRewardsVault.UserState memory beforeState = vault.getUserState(poolId, ALICE);
        assertGt(beforeState.activeWeight, 0);

        _hookModify(-int256(20 ether), abi.encode(ALICE));

        IRewardsVault.UserState memory afterState = vault.getUserState(poolId, ALICE);
        assertLt(afterState.activeWeight, beforeState.activeWeight);
    }

    function testBeforeAddLiquidityRejectsInvalidHookDataLength() public {
        _createStreamingProgram(1 ether, 10, 1 days, 500);
        vm.expectRevert(IncentivesHook.InvalidHookData.selector);
        _hookModify(int256(10 ether), bytes(""));
    }

    function testBeforeAddLiquidityRejectsZeroAddressHookData() public {
        _createStreamingProgram(1 ether, 10, 1 days, 500);
        vm.expectRevert(IncentivesHook.InvalidHookData.selector);
        _hookModify(int256(10 ether), abi.encode(address(0)));
    }

    function testAdapterFundRevertsForUnapprovedAdapter() public {
        _createStreamingProgram(1 ether, 0, 0, 0);
        router.setAdapter(address(adapter), false);

        vm.prank(address(adapter));
        vm.expectRevert(RevenueRouter.AdapterNotApproved.selector);
        router.adapterFund(poolId, 1 ether);
    }

    function testAdapterFundRevertsForMissingProgram() public {
        router.setAdapter(address(adapter), true);

        vm.prank(address(adapter));
        vm.expectRevert(RevenueRouter.ProgramNotConfigured.selector);
        router.adapterFund(bytes32(uint256(999)), 1 ether);
    }
}
