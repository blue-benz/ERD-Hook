// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {RewardsVault} from "../../src/RewardsVault.sol";
import {IRewardsVault} from "../../src/interfaces/IRewardsVault.sol";
import {MockRewardToken} from "../../src/mocks/MockRewardToken.sol";

contract RewardsVaultFuzzTest is Test {
    bytes32 internal constant POOL_ID = keccak256("fuzz-pool");

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

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
            warmupPeriod: 5,
            cooldownPeriod: 1 days,
            earlyWithdrawalPenaltyBps: 1_000,
            emissionRate: 1 ether,
            maxFunding: type(uint128).max
        });

        vault.registerProgram(POOL_ID, config);
    }

    function testFuzz_TotalClaimedNeverExceedsFunded(
        uint128 fundA,
        uint128 fundB,
        uint96 liqA,
        uint96 liqB,
        uint40 dt1,
        uint40 dt2
    ) public {
        fundA = uint128(bound(fundA, 1 ether, 1_000_000 ether));
        fundB = uint128(bound(fundB, 1 ether, 1_000_000 ether));
        liqA = uint96(bound(liqA, 1 ether, 1_000_000 ether));
        liqB = uint96(bound(liqB, 1 ether, 1_000_000 ether));
        dt1 = uint40(bound(dt1, 1 minutes, 7 days));
        dt2 = uint40(bound(dt2, 1 minutes, 7 days));

        rewardToken.mint(address(vault), uint256(fundA) + uint256(fundB));

        vault.fundProgram(POOL_ID, fundA, address(this));
        vault.onLiquidityDelta(POOL_ID, ALICE, int256(uint256(liqA)));

        vm.warp(block.timestamp + dt1);

        vault.fundProgram(POOL_ID, fundB, address(this));
        vault.onLiquidityDelta(POOL_ID, BOB, int256(uint256(liqB)));

        vm.warp(block.timestamp + dt2);

        vm.prank(ALICE);
        vault.claim(POOL_ID, ALICE, ALICE);

        vm.prank(BOB);
        vault.claim(POOL_ID, BOB, BOB);

        IRewardsVault.ProgramState memory state = vault.getProgramState(POOL_ID);

        assertLe(state.totalClaimed, state.totalFunded);
        assertLe(state.totalDistributed, state.totalFunded);
        assertLe(state.totalClaimed, state.totalDistributed);
    }

    function testFuzz_WarmupInvariant(uint96 liqA, uint40 warpForward) public {
        liqA = uint96(bound(liqA, 1 ether, 1_000_000 ether));
        warpForward = uint40(bound(warpForward, 1 seconds, 4 seconds));

        rewardToken.mint(address(vault), 1_000 ether);
        vault.fundProgram(POOL_ID, 1_000 ether, address(this));

        vault.onLiquidityDelta(POOL_ID, ALICE, int256(uint256(liqA)));

        vm.warp(block.timestamp + warpForward);

        uint256 preview = vault.claimable(POOL_ID, ALICE);
        assertEq(preview, 0);
    }
}
