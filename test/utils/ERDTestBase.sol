// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {IncentiveController} from "../../src/IncentiveController.sol";
import {IncentivesHook} from "../../src/IncentivesHook.sol";
import {RevenueRouter} from "../../src/RevenueRouter.sol";
import {RewardsVault} from "../../src/RewardsVault.sol";
import {IRewardsVault} from "../../src/interfaces/IRewardsVault.sol";
import {IIncentiveController} from "../../src/interfaces/IIncentiveController.sol";
import {IRevenueRouter} from "../../src/interfaces/IRevenueRouter.sol";
import {MockRewardToken} from "../../src/mocks/MockRewardToken.sol";
import {MockRevenueAdapter, IMintableERC20} from "../../src/mocks/MockRevenueAdapter.sol";
import {EasyPosm} from "./libraries/EasyPosm.sol";

import {BaseTest} from "./BaseTest.sol";

abstract contract ERDTestBase is BaseTest {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using EasyPosm for IPositionManager;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA001);

    Currency internal currency0;
    Currency internal currency1;
    MockERC20 internal token0;
    MockERC20 internal token1;

    PoolKey internal poolKey;
    bytes32 internal poolId;

    IncentiveController internal controller;
    IncentivesHook internal hook;
    RevenueRouter internal router;
    RewardsVault internal vault;
    MockRewardToken internal rewardToken;
    MockRevenueAdapter internal adapter;

    int24 internal tickLower;
    int24 internal tickUpper;

    function setUp() public virtual {
        deployArtifactsAndLabel();
        (currency0, currency1) = deployCurrencyPair();

        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));

        rewardToken = new MockRewardToken("Reward Token", "RWD");
        vault = new RewardsVault(address(this));
        controller = new IncentiveController(address(this), IRewardsVault(address(vault)), 1 hours);
        router = new RevenueRouter(address(this), IIncentiveController(address(controller)), IRewardsVault(address(vault)));
        adapter =
            new MockRevenueAdapter(address(this), IMintableERC20(address(rewardToken)), IRevenueRouter(address(router)));

        vault.setController(address(controller));
        controller.setRevenueRouter(address(router));
        router.setAdapter(address(adapter), true);

        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x7777 << 144)
        );

        bytes memory constructorArgs = abi.encode(poolManager, controller);
        deployCodeTo("IncentivesHook.sol:IncentivesHook", constructorArgs, flags);
        hook = IncentivesHook(flags);

        controller.setHook(address(hook));

        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = PoolId.unwrap(poolKey.toId());

        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        _seedLp(ALICE);
        _seedLp(BOB);
        _seedLp(CAROL);
    }

    function _createStreamingProgram(uint96 emissionRate, uint40 warmup, uint40 cooldown, uint16 penaltyBps) internal {
        IRewardsVault.ProgramConfig memory config = IRewardsVault.ProgramConfig({
            rewardToken: address(rewardToken),
            distributionType: IRewardsVault.DistributionType.STREAMING,
            startTime: uint40(block.timestamp),
            endTime: 0,
            warmupPeriod: warmup,
            cooldownPeriod: cooldown,
            earlyWithdrawalPenaltyBps: penaltyBps,
            emissionRate: emissionRate,
            maxFunding: type(uint128).max
        });

        controller.createProgram(poolKey, config);
    }

    function _createEpochProgram(
        uint96 emissionRate,
        uint40 startTime,
        uint40 endTime,
        uint40 warmup,
        uint40 cooldown,
        uint16 penaltyBps
    ) internal {
        IRewardsVault.ProgramConfig memory config = IRewardsVault.ProgramConfig({
            rewardToken: address(rewardToken),
            distributionType: IRewardsVault.DistributionType.EPOCH,
            startTime: startTime,
            endTime: endTime,
            warmupPeriod: warmup,
            cooldownPeriod: cooldown,
            earlyWithdrawalPenaltyBps: penaltyBps,
            emissionRate: emissionRate,
            maxFunding: type(uint128).max
        });

        controller.createProgram(poolKey, config);
    }

    function _fundDirect(uint256 amount) internal {
        rewardToken.mint(address(this), amount);
        rewardToken.approve(address(router), amount);
        router.directFund(poolId, amount);
    }

    function _fundViaAdapter(uint256 amount) internal {
        adapter.mintRevenue(amount);
        adapter.routeRevenue(poolId, amount);
    }

    function _mintLiquidity(address lp, uint128 liquidityAmount) internal returns (uint256 tokenId) {
        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        vm.prank(lp);
        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            lp,
            block.timestamp + 1,
            abi.encode(lp)
        );
    }

    function _decreaseLiquidity(address lp, uint256 tokenId, uint256 liquidityAmount) internal {
        tokenId; // keep signature parity with mint-based tests
        vm.prank(address(hook));
        controller.onLiquidityChanged(poolId, lp, -int256(liquidityAmount));
    }

    function _activateMaturedWeight(address lp) internal {
        vm.prank(address(hook));
        controller.onLiquidityChanged(poolId, lp, int256(1));
        vm.prank(address(hook));
        controller.onLiquidityChanged(poolId, lp, -int256(1));
    }

    function _seedLp(address lp) internal {
        token0.mint(lp, 1_000_000 ether);
        token1.mint(lp, 1_000_000 ether);

        vm.startPrank(lp);
        token0.approve(address(permit2), type(uint256).max);
        token1.approve(address(permit2), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);

        permit2.approve(address(token0), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token0), address(poolManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1), address(poolManager), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }
}
