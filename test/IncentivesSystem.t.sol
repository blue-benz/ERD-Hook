// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {IncentivesHook} from "../src/IncentivesHook.sol";
import {IRewardsVault} from "../src/interfaces/IRewardsVault.sol";
import {ERDTestBase} from "./utils/ERDTestBase.sol";

contract IncentivesSystemTest is ERDTestBase {
    function testStreamingRewardsFairness() public {
        _createStreamingProgram(1 ether, 60, 1 days, 1_000);
        _fundDirect(1_000 ether);
        _fundViaAdapter(500 ether);

        uint256 aliceTokenId = _mintLiquidity(ALICE, 100 ether);
        assertGt(aliceTokenId, 0);

        vm.warp(block.timestamp + 120);
        _activateMaturedWeight(ALICE);

        uint256 bobTokenId = _mintLiquidity(BOB, 100 ether);
        assertGt(bobTokenId, 0);

        vm.warp(block.timestamp + 300);
        _activateMaturedWeight(BOB);
        vm.warp(block.timestamp + 120);

        vm.prank(ALICE);
        uint256 aliceClaim = controller.claim(poolId, ALICE);

        vm.prank(BOB);
        uint256 bobClaim = controller.claim(poolId, BOB);

        assertGt(aliceClaim, bobClaim);

        IRewardsVault.ProgramState memory state = vault.getProgramState(poolId);
        assertLe(state.totalClaimed, state.totalFunded);
    }

    function testEarlyWithdrawalPenaltyApplied() public {
        _createStreamingProgram(1 ether, 60, 7 days, 2_000);
        _fundDirect(500 ether);

        uint256 bobTokenId = _mintLiquidity(BOB, 80 ether);

        vm.warp(block.timestamp + 180);
        _activateMaturedWeight(BOB);
        vm.warp(block.timestamp + 30);
        _decreaseLiquidity(BOB, bobTokenId, 40 ether);

        vm.prank(BOB);
        uint256 bobClaim = controller.claim(poolId, BOB);

        IRewardsVault.ProgramState memory state = vault.getProgramState(poolId);

        assertGt(state.totalSlashed, 0);
        assertGt(bobClaim, 0);
    }

    function testClaimTwiceReturnsZeroOnSecondClaim() public {
        _createStreamingProgram(2 ether, 1, 1 days, 0);
        _fundDirect(100 ether);

        _mintLiquidity(ALICE, 50 ether);
        vm.warp(block.timestamp + 100);
        _activateMaturedWeight(ALICE);
        vm.warp(block.timestamp + 60);

        vm.prank(ALICE);
        uint256 firstClaim = controller.claim(poolId, ALICE);

        vm.prank(ALICE);
        uint256 secondClaim = controller.claim(poolId, ALICE);

        assertGt(firstClaim, 0);
        assertEq(secondClaim, 0);
    }

    function testSwapHooksUpdateMetrics() public {
        _createStreamingProgram(1 ether, 10, 1 days, 0);
        _fundDirect(100 ether);

        _mintLiquidity(ALICE, 200 ether);

        vm.warp(block.timestamp + 20);

        BalanceDelta delta = swapRouter.swapExactTokensForTokens({
            amountIn: 1 ether,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: abi.encode(ALICE),
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        assertEq(int256(delta.amount0()), -1 ether);
        assertEq(hook.beforeSwapCount(poolId), 1);
        assertEq(hook.afterSwapCount(poolId), 1);
        assertEq(controller.observedSwapCount(poolId), 1);
        assertGt(controller.observedSwapVolume(poolId), 0);
    }

    function testProgramWithoutLiquidityKeepsFundingUndistributed() public {
        _createStreamingProgram(1 ether, 1, 1 days, 0);
        _fundDirect(100 ether);

        vm.warp(block.timestamp + 1 days);

        IRewardsVault.ProgramState memory state = vault.getProgramState(poolId);

        assertEq(state.totalDistributed, 0);
        assertEq(state.fundedBalance, 100 ether);
    }

    function testOnlyOwnerCanQueueProgramUpdate() public {
        _createStreamingProgram(1 ether, 1, 1 days, 0);

        IRewardsVault.ProgramConfig memory config = IRewardsVault.ProgramConfig({
            rewardToken: address(rewardToken),
            distributionType: IRewardsVault.DistributionType.STREAMING,
            startTime: uint40(block.timestamp),
            endTime: 0,
            warmupPeriod: 10,
            cooldownPeriod: 10,
            earlyWithdrawalPenaltyBps: 100,
            emissionRate: 2 ether,
            maxFunding: type(uint128).max
        });

        vm.prank(ALICE);
        vm.expectRevert();
        controller.queueProgramUpdate(poolId, config);
    }

    function testPermissionBitMismatchReverts() public {
        address invalidFlags = address(uint160(Hooks.BEFORE_SWAP_FLAG) ^ (0x8888 << 144));
        bytes memory constructorArgs = abi.encode(poolManager, controller);

        vm.expectRevert();
        deployCodeTo("IncentivesHook.sol:IncentivesHook", constructorArgs, invalidFlags);
    }
}
