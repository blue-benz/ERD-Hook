// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IRewardsVault} from "../src/interfaces/IRewardsVault.sol";
import {ERDTestBase} from "./utils/ERDTestBase.sol";

contract EpochDistributionTest is ERDTestBase {
    function testEpochFundingMidEpochAndRollover() public {
        uint40 epochStart = uint40(block.timestamp);
        uint40 epochEnd = epochStart + 1 days;

        _createEpochProgram(1 ether, epochStart, epochEnd, 30, 1 days, 500);
        _fundDirect(2_000 ether);

        _mintLiquidity(ALICE, 150 ether);

        vm.warp(block.timestamp + 6 hours);
        _activateMaturedWeight(ALICE);
        _fundViaAdapter(500 ether);

        vm.warp(block.timestamp + 6 hours);
        _mintLiquidity(BOB, 150 ether);
        vm.warp(block.timestamp + 1 hours);
        _activateMaturedWeight(BOB);

        vm.warp(epochEnd + 1);

        vm.prank(ALICE);
        uint256 aliceClaim = controller.claim(poolId, ALICE);

        vm.prank(BOB);
        uint256 bobClaim = controller.claim(poolId, BOB);

        assertGt(aliceClaim, bobClaim);

        uint40 nextStart = uint40(block.timestamp);
        uint40 nextEnd = nextStart + 1 days;
        controller.rollEpoch(poolId, nextStart, nextEnd, 2 ether);

        IRewardsVault.ProgramConfig memory cfg = controller.getProgramConfig(poolId);
        assertEq(cfg.startTime, nextStart);
        assertEq(cfg.endTime, nextEnd);
        assertEq(cfg.emissionRate, 2 ether);
    }

    function testWithdrawBeforeWarmupCompletesGetsNoRewards() public {
        _createEpochProgram(1 ether, uint40(block.timestamp), uint40(block.timestamp + 1 days), 1 days, 1 days, 0);
        _fundDirect(500 ether);

        uint256 aliceTokenId = _mintLiquidity(ALICE, 80 ether);
        _decreaseLiquidity(ALICE, aliceTokenId, 80 ether);

        vm.prank(ALICE);
        uint256 claimAmount = controller.claim(poolId, ALICE);

        assertEq(claimAmount, 0);
    }

    function testFundingUnknownProgramReverts() public {
        rewardToken.mint(address(this), 10 ether);
        rewardToken.approve(address(router), 10 ether);

        vm.expectRevert();
        router.directFund(bytes32(uint256(12345)), 10 ether);
    }
}
