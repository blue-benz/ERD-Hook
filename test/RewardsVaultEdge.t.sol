// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {RewardsVault} from "../src/RewardsVault.sol";
import {IRewardsVault} from "../src/interfaces/IRewardsVault.sol";
import {MockRewardToken} from "../src/mocks/MockRewardToken.sol";

contract RewardsVaultEdgeTest is Test {
    bytes32 internal constant POOL_ID = keccak256("edge-pool");

    address internal constant ALICE = address(0xA11CE);

    RewardsVault internal vault;
    MockRewardToken internal rewardToken;

    function setUp() public {
        rewardToken = new MockRewardToken("Reward", "RWD");
        vault = new RewardsVault(address(this));
        vault.setController(address(this));
        vault.setRouter(address(this));

        IRewardsVault.ProgramConfig memory config = IRewardsVault.ProgramConfig({
            rewardToken: address(rewardToken),
            distributionType: IRewardsVault.DistributionType.STREAMING,
            startTime: uint40(block.timestamp),
            endTime: 0,
            warmupPeriod: 0,
            cooldownPeriod: 100,
            earlyWithdrawalPenaltyBps: 500,
            emissionRate: 1 ether,
            maxFunding: type(uint128).max
        });

        vault.registerProgram(POOL_ID, config);
    }

    function testClaimForDifferentLpReverts() public {
        rewardToken.mint(address(vault), 100 ether);
        vault.fundProgram(POOL_ID, 100 ether, address(this));
        vault.onLiquidityDelta(POOL_ID, ALICE, int256(100 ether));
        vault.onLiquidityDelta(POOL_ID, ALICE, int256(1));
        vault.onLiquidityDelta(POOL_ID, ALICE, -int256(1));

        vm.warp(block.timestamp + 100);

        vm.prank(ALICE);
        vm.expectRevert();
        vault.claim(POOL_ID, address(0xB0B), ALICE);
    }

    function testDoubleClaimReturnsZero() public {
        rewardToken.mint(address(vault), 100 ether);
        vault.fundProgram(POOL_ID, 100 ether, address(this));
        vault.onLiquidityDelta(POOL_ID, ALICE, int256(100 ether));
        vault.onLiquidityDelta(POOL_ID, ALICE, int256(1));
        vault.onLiquidityDelta(POOL_ID, ALICE, -int256(1));

        vm.warp(block.timestamp + 100);

        vm.prank(ALICE);
        uint256 first = vault.claim(POOL_ID, ALICE, ALICE);

        vm.prank(ALICE);
        uint256 second = vault.claim(POOL_ID, ALICE, ALICE);

        assertGt(first, 0);
        assertEq(second, 0);
    }

    function testFundingCapRespected() public {
        IRewardsVault.ProgramConfig memory config = IRewardsVault.ProgramConfig({
            rewardToken: address(rewardToken),
            distributionType: IRewardsVault.DistributionType.STREAMING,
            startTime: uint40(block.timestamp),
            endTime: 0,
            warmupPeriod: 0,
            cooldownPeriod: 0,
            earlyWithdrawalPenaltyBps: 0,
            emissionRate: 1 ether,
            maxFunding: 50 ether
        });

        bytes32 boundedPool = keccak256("bounded");
        vault.registerProgram(boundedPool, config);

        rewardToken.mint(address(vault), 100 ether);
        vault.fundProgram(boundedPool, 40 ether, address(this));

        vm.expectRevert();
        vault.fundProgram(boundedPool, 20 ether, address(this));
    }
}
