// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {RewardsVault} from "../src/RewardsVault.sol";
import {IRewardsVault} from "../src/interfaces/IRewardsVault.sol";
import {MockRewardToken} from "../src/mocks/MockRewardToken.sol";

contract CoverageRewardsVaultTest is Test {
    bytes32 internal constant STREAM_POOL = keccak256("stream-pool");
    bytes32 internal constant EPOCH_POOL = keccak256("epoch-pool");

    address internal constant ALICE = address(0xA11CE);

    RewardsVault internal vault;
    MockRewardToken internal rewardToken;
    MockRewardToken internal otherToken;

    function setUp() public {
        rewardToken = new MockRewardToken("Reward", "RWD");
        otherToken = new MockRewardToken("Other", "OTR");

        vault = new RewardsVault(address(this));
        vault.setController(address(this));
        vault.setRouter(address(this));

        vault.registerProgram(STREAM_POOL, _streamConfig(uint40(block.timestamp), 0, 0, 1 ether, type(uint128).max));
        vault.registerProgram(
            EPOCH_POOL,
            _epochConfig(uint40(block.timestamp), uint40(block.timestamp + 1 days), 0, 1 ether, type(uint128).max)
        );
    }

    function _streamConfig(uint40 startTime, uint40 endTime, uint40 warmup, uint96 emissionRate, uint256 maxFunding)
        internal
        view
        returns (IRewardsVault.ProgramConfig memory)
    {
        return IRewardsVault.ProgramConfig({
            rewardToken: address(rewardToken),
            distributionType: IRewardsVault.DistributionType.STREAMING,
            startTime: startTime,
            endTime: endTime,
            warmupPeriod: warmup,
            cooldownPeriod: 1 days,
            earlyWithdrawalPenaltyBps: 1_000,
            emissionRate: emissionRate,
            maxFunding: maxFunding
        });
    }

    function _epochConfig(uint40 startTime, uint40 endTime, uint40 warmup, uint96 emissionRate, uint256 maxFunding)
        internal
        view
        returns (IRewardsVault.ProgramConfig memory)
    {
        return IRewardsVault.ProgramConfig({
            rewardToken: address(rewardToken),
            distributionType: IRewardsVault.DistributionType.EPOCH,
            startTime: startTime,
            endTime: endTime,
            warmupPeriod: warmup,
            cooldownPeriod: 1 days,
            earlyWithdrawalPenaltyBps: 1_000,
            emissionRate: emissionRate,
            maxFunding: maxFunding
        });
    }

    function _fund(bytes32 poolId, uint256 amount) internal {
        rewardToken.mint(address(vault), amount);
        vault.fundProgram(poolId, amount, address(this));
    }

    function _activateWeight(bytes32 poolId, address lp) internal {
        vault.onLiquidityDelta(poolId, lp, int256(1));
        vault.onLiquidityDelta(poolId, lp, -int256(1));
    }

    function testSetControllerValidationAndSingleAssignment() public {
        RewardsVault localVault = new RewardsVault(address(this));

        vm.expectRevert(RewardsVault.InvalidConfig.selector);
        localVault.setController(address(0));

        localVault.setController(address(this));
        vm.expectRevert(RewardsVault.ControllerAlreadySet.selector);
        localVault.setController(address(0xBEEF));
    }

    function testSetRouterOnlyController() public {
        vault.setRouter(address(0xBEEF));
        IRewardsVault.ProgramState memory state = vault.getProgramState(STREAM_POOL);
        assertTrue(state.exists);

        vm.prank(ALICE);
        vm.expectRevert(RewardsVault.NotController.selector);
        vault.setRouter(ALICE);
    }

    function testOnlyControllerModifierLowLevelRevertPath() public {
        vm.prank(ALICE);
        (bool ok,) = address(vault).call(abi.encodeWithSelector(vault.setRouter.selector, ALICE));
        assertFalse(ok);
    }

    function testRegisterProgramValidationAndExistsGuard() public {
        vm.expectRevert(RewardsVault.ProgramExists.selector);
        vault.registerProgram(STREAM_POOL, _streamConfig(uint40(block.timestamp), 0, 0, 1 ether, type(uint128).max));

        IRewardsVault.ProgramConfig memory invalid = _streamConfig(uint40(block.timestamp), 0, 0, 1 ether, type(uint128).max);
        invalid.rewardToken = address(0);
        vm.expectRevert(RewardsVault.InvalidConfig.selector);
        vault.registerProgram(keccak256("invalid-reward-token"), invalid);

        invalid = _streamConfig(uint40(block.timestamp), 0, 0, 1 ether, type(uint128).max);
        invalid.earlyWithdrawalPenaltyBps = 10_001;
        vm.expectRevert(RewardsVault.InvalidConfig.selector);
        vault.registerProgram(keccak256("invalid-penalty"), invalid);

        IRewardsVault.ProgramConfig memory invalidEpoch =
            _epochConfig(uint40(block.timestamp), uint40(block.timestamp), 0, 1 ether, type(uint128).max);
        vm.expectRevert(RewardsVault.InvalidConfig.selector);
        vault.registerProgram(keccak256("invalid-epoch-window"), invalidEpoch);
    }

    function testUpdateProgramConfigValidationAndSuccessPath() public {
        IRewardsVault.ProgramConfig memory cfg = _streamConfig(uint40(block.timestamp), 0, 0, 1 ether, type(uint128).max);

        vm.expectRevert(RewardsVault.ProgramNotFound.selector);
        vault.updateProgramConfig(bytes32(uint256(123)), cfg);

        cfg.rewardToken = address(otherToken);
        vm.expectRevert(RewardsVault.RewardTokenImmutable.selector);
        vault.updateProgramConfig(STREAM_POOL, cfg);

        cfg = _streamConfig(0, 0, 25, 2 ether, 10_000 ether);
        cfg.cooldownPeriod = 3 days;
        cfg.earlyWithdrawalPenaltyBps = 500;
        vault.updateProgramConfig(STREAM_POOL, cfg);

        IRewardsVault.ProgramState memory state = vault.getProgramState(STREAM_POOL);
        assertEq(state.emissionRate, 2 ether);
        assertEq(state.cooldownPeriod, 3 days);
        assertEq(state.warmupPeriod, 25);
        assertEq(state.earlyWithdrawalPenaltyBps, 500);
    }

    function testFundingGuards() public {
        vm.prank(ALICE);
        vm.expectRevert(RewardsVault.NotRouter.selector);
        vault.fundProgram(STREAM_POOL, 1 ether, ALICE);

        vm.expectRevert(RewardsVault.ProgramNotFound.selector);
        vault.fundProgram(bytes32(uint256(333)), 1 ether, address(this));
    }

    function testLiquidityDeltaGuardsAndInsufficientWeight() public {
        vm.prank(ALICE);
        vm.expectRevert(RewardsVault.NotController.selector);
        vault.onLiquidityDelta(STREAM_POOL, ALICE, int256(1));

        vm.expectRevert(RewardsVault.InvalidLiquidityDelta.selector);
        vault.onLiquidityDelta(STREAM_POOL, ALICE, int256(0));

        vm.expectRevert(RewardsVault.ProgramNotFound.selector);
        vault.onLiquidityDelta(bytes32(uint256(777)), ALICE, int256(1));

        vault.onLiquidityDelta(STREAM_POOL, ALICE, int256(10 ether));
        vm.expectRevert(RewardsVault.InsufficientWeight.selector);
        vault.onLiquidityDelta(STREAM_POOL, ALICE, -int256(20 ether));
    }

    function testRollEpochGuards() public {
        vm.expectRevert(RewardsVault.InvalidEpochWindow.selector);
        vault.rollEpoch(EPOCH_POOL, uint40(block.timestamp + 1), uint40(block.timestamp + 1), 1 ether);

        vm.expectRevert(RewardsVault.ProgramNotFound.selector);
        vault.rollEpoch(bytes32(uint256(1_111)), uint40(block.timestamp), uint40(block.timestamp + 10), 1 ether);

        vm.expectRevert(RewardsVault.InvalidConfig.selector);
        vault.rollEpoch(STREAM_POOL, uint40(block.timestamp), uint40(block.timestamp + 10), 1 ether);
    }

    function testClaimAndClaimableGuards() public {
        assertEq(vault.claimable(bytes32(uint256(9_999)), ALICE), 0);

        vm.prank(ALICE);
        vm.expectRevert(RewardsVault.ProgramNotFound.selector);
        vault.claim(bytes32(uint256(9_999)), ALICE, ALICE);
    }

    function testClaimableImmediateWindowAndUserStateGetter() public {
        vault.onLiquidityDelta(STREAM_POOL, ALICE, int256(5 ether));
        IRewardsVault.UserState memory userState = vault.getUserState(STREAM_POOL, ALICE);
        assertEq(userState.pendingWeight, 5 ether);

        uint256 preview = vault.claimable(STREAM_POOL, ALICE);
        assertEq(preview, 0);
    }

    function testPreviewAccCapsRewardsByFundedBalance() public {
        bytes32 cappedPool = keccak256("capped-preview");
        vault.registerProgram(cappedPool, _streamConfig(uint40(block.timestamp), 0, 0, 10 ether, type(uint128).max));

        _fund(cappedPool, 1 ether);
        vault.onLiquidityDelta(cappedPool, ALICE, int256(10 ether));
        _activateWeight(cappedPool, ALICE);

        vm.warp(block.timestamp + 5);

        uint256 preview = vault.claimable(cappedPool, ALICE);
        assertEq(preview, 1 ether);
    }

    function testDistributionWindowReturnsZeroWhenEndBeforeStart() public {
        uint40 nowTs = uint40(block.timestamp);
        bytes32 weirdPool = keccak256("weird-window");

        vault.registerProgram(weirdPool, _streamConfig(nowTs + 1 days, nowTs + 1 hours, 0, 1 ether, type(uint128).max));
        _fund(weirdPool, 10 ether);

        vault.onLiquidityDelta(weirdPool, ALICE, int256(10 ether));
        _activateWeight(weirdPool, ALICE);
        vm.warp(block.timestamp + 30 minutes);

        uint256 preview = vault.claimable(weirdPool, ALICE);
        assertEq(preview, 0);
    }
}
