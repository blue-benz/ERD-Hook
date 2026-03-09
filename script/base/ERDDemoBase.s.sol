// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

import {Deployers} from "../../test/utils/Deployers.sol";
import {EasyPosm} from "../../test/utils/libraries/EasyPosm.sol";

import {IncentiveController} from "../../src/IncentiveController.sol";
import {IncentivesHook} from "../../src/IncentivesHook.sol";
import {RevenueRouter} from "../../src/RevenueRouter.sol";
import {RewardsVault} from "../../src/RewardsVault.sol";
import {IRewardsVault} from "../../src/interfaces/IRewardsVault.sol";
import {IIncentiveController} from "../../src/interfaces/IIncentiveController.sol";
import {IRevenueRouter} from "../../src/interfaces/IRevenueRouter.sol";
import {MockRewardToken} from "../../src/mocks/MockRewardToken.sol";
import {MockRevenueAdapter, IMintableERC20} from "../../src/mocks/MockRevenueAdapter.sol";

abstract contract ERDDemoBase is Script, Deployers {
    using PoolIdLibrary for PoolKey;
    using EasyPosm for IPositionManager;
    using CurrencyLibrary for Currency;

    uint128 internal constant LP_LIQUIDITY = 100 ether;
    uint256 internal constant DIRECT_FUNDING = 1_000 ether;
    uint256 internal constant ADAPTER_FUNDING = 500 ether;

    uint256 internal constant DEFAULT_DEPLOYER_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 internal constant DEFAULT_LP_A_KEY =
        0x59c6995e998f97a5a0044966f0945386c5f8b0ef4f14f7a0d4f0de96f0f8f0b3;
    uint256 internal constant DEFAULT_LP_B_KEY =
        0x5de4111afa1a4b94908f83103f9dce85de09f37bc6538f0f3df8d72f3f4bfad6;

    struct DemoState {
        uint256 deployerKey;
        uint256 lpAKey;
        uint256 lpBKey;
        address deployer;
        address lpA;
        address lpB;
        MockERC20 token0;
        MockERC20 token1;
        MockRewardToken rewardToken;
        RewardsVault vault;
        IncentiveController controller;
        RevenueRouter router;
        MockRevenueAdapter adapter;
        IncentivesHook hook;
        PoolKey poolKey;
        bytes32 poolId;
        int24 tickLower;
        int24 tickUpper;
    }

    function _etch(address target, bytes memory bytecode) internal override {
        if (block.chainid == 31337) {
            vm.rpc("anvil_setCode", string.concat('["', vm.toString(target), '",', '"', vm.toString(bytecode), '"]'));
        } else {
            revert("Unsupported etch outside local network");
        }
    }

    function _keyOrDefault(string memory envName, uint256 fallbackKey) internal view returns (uint256) {
        return vm.envOr(envName, fallbackKey);
    }

    function _runDemo(IRewardsVault.DistributionType distributionType) internal {
        DemoState memory s;

        s.deployerKey = _keyOrDefault("PRIVATE_KEY", DEFAULT_DEPLOYER_KEY);
        s.lpAKey = _keyOrDefault("LP_A_PRIVATE_KEY", DEFAULT_LP_A_KEY);
        s.lpBKey = _keyOrDefault("LP_B_PRIVATE_KEY", DEFAULT_LP_B_KEY);

        s.deployer = vm.addr(s.deployerKey);
        s.lpA = vm.addr(s.lpAKey);
        s.lpB = vm.addr(s.lpBKey);

        vm.startBroadcast(s.deployerKey);

        deployArtifacts();

        (s.token0, s.token1) = _deployTokenPair();

        s.rewardToken = new MockRewardToken("Reward Token", "RWD");
        s.vault = new RewardsVault(s.deployer);
        s.controller = new IncentiveController(s.deployer, IRewardsVault(address(s.vault)), 1 hours);
        s.router = new RevenueRouter(
            s.deployer,
            IIncentiveController(address(s.controller)),
            IRewardsVault(address(s.vault))
        );
        s.adapter = new MockRevenueAdapter(
            s.deployer,
            IMintableERC20(address(s.rewardToken)),
            IRevenueRouter(address(s.router))
        );

        s.vault.setController(address(s.controller));
        s.controller.setRevenueRouter(address(s.router));
        s.router.setAdapter(address(s.adapter), true);

        s.hook = _deployHook(poolManager, s.controller);
        s.controller.setHook(address(s.hook));

        s.poolKey = PoolKey(
            Currency.wrap(address(s.token0)),
            Currency.wrap(address(s.token1)),
            3000,
            60,
            IHooks(s.hook)
        );
        s.poolId = PoolId.unwrap(s.poolKey.toId());

        poolManager.initialize(s.poolKey, Constants.SQRT_PRICE_1_1);

        s.tickLower = TickMath.minUsableTick(s.poolKey.tickSpacing);
        s.tickUpper = TickMath.maxUsableTick(s.poolKey.tickSpacing);

        _createProgram(s, distributionType);

        _fundProgram(s);

        vm.stopBroadcast();

        _prepareLpWallet(s.lpAKey, s.token0, s.token1);
        _prepareLpWallet(s.lpBKey, s.token0, s.token1);

        _mintForLp(s, s.lpAKey, s.lpA, LP_LIQUIDITY);

        if (block.chainid == 31337) {
            vm.warp(block.timestamp + 1 hours);
        }

        _mintForLp(s, s.lpBKey, s.lpB, LP_LIQUIDITY);

        if (block.chainid == 31337) {
            vm.warp(block.timestamp + 30 minutes);
        }

        _runSwap(s);

        if (distributionType == IRewardsVault.DistributionType.EPOCH && block.chainid == 31337) {
            vm.warp(block.timestamp + 1 days + 1);
        }

        uint256 claimA = _claimForLp(s.lpAKey, s.controller, s.poolId, s.lpA);
        uint256 claimB = _claimForLp(s.lpBKey, s.controller, s.poolId, s.lpB);

        IRewardsVault.ProgramState memory state = s.vault.getProgramState(s.poolId);

        console2.log("=== ERD Demo Summary ===");
        console2.log("deployer", s.deployer);
        console2.log("lpA", s.lpA);
        console2.log("lpB", s.lpB);
        console2.log("poolId", uint256(s.poolId));
        console2.log("hook", address(s.hook));
        console2.log("controller", address(s.controller));
        console2.log("router", address(s.router));
        console2.log("vault", address(s.vault));
        console2.log("rewardToken", address(s.rewardToken));
        console2.log("directFunding", DIRECT_FUNDING);
        console2.log("adapterFunding", ADAPTER_FUNDING);
        console2.log("totalFunded", state.totalFunded);
        console2.log("totalActiveWeight", state.totalActiveWeight);
        console2.log("claimA", claimA);
        console2.log("claimB", claimB);
        console2.log("totalSlashed", state.totalSlashed);
    }

    function _deployTokenPair() internal returns (MockERC20 token0_, MockERC20 token1_) {
        MockERC20 tokenA = new MockERC20("LP Token A", "LPA", 18);
        MockERC20 tokenB = new MockERC20("LP Token B", "LPB", 18);

        (token0_, token1_) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        token0_.mint(msg.sender, 5_000_000 ether);
        token1_.mint(msg.sender, 5_000_000 ether);
        token0_.mint(vm.addr(_keyOrDefault("LP_A_PRIVATE_KEY", DEFAULT_LP_A_KEY)), 1_000_000 ether);
        token1_.mint(vm.addr(_keyOrDefault("LP_A_PRIVATE_KEY", DEFAULT_LP_A_KEY)), 1_000_000 ether);
        token0_.mint(vm.addr(_keyOrDefault("LP_B_PRIVATE_KEY", DEFAULT_LP_B_KEY)), 1_000_000 ether);
        token1_.mint(vm.addr(_keyOrDefault("LP_B_PRIVATE_KEY", DEFAULT_LP_B_KEY)), 1_000_000 ether);

        token0_.approve(address(permit2), type(uint256).max);
        token1_.approve(address(permit2), type(uint256).max);
        token0_.approve(address(swapRouter), type(uint256).max);
        token1_.approve(address(swapRouter), type(uint256).max);

        permit2.approve(address(token0_), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1_), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token0_), address(poolManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1_), address(poolManager), type(uint160).max, type(uint48).max);
    }

    function _deployHook(IPoolManager poolManager_, IncentiveController controller_) internal returns (IncentivesHook hook_) {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        bytes memory constructorArgs = abi.encode(poolManager_, controller_);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(IncentivesHook).creationCode, constructorArgs);

        hook_ = new IncentivesHook{salt: salt}(poolManager_, controller_);
        require(address(hook_) == hookAddress, "Hook address mismatch");
    }

    function _createProgram(DemoState memory s, IRewardsVault.DistributionType distributionType) internal {
        uint40 start = uint40(block.timestamp);
        uint40 end = distributionType == IRewardsVault.DistributionType.EPOCH ? start + 1 days : 0;

        IRewardsVault.ProgramConfig memory config = IRewardsVault.ProgramConfig({
            rewardToken: address(s.rewardToken),
            distributionType: distributionType,
            startTime: start,
            endTime: end,
            warmupPeriod: 0,
            cooldownPeriod: 1 days,
            earlyWithdrawalPenaltyBps: 1_000,
            emissionRate: 1 ether,
            maxFunding: type(uint128).max
        });

        s.controller.createProgram(s.poolKey, config);
    }

    function _fundProgram(DemoState memory s) internal {
        s.rewardToken.mint(msg.sender, DIRECT_FUNDING);
        s.rewardToken.approve(address(s.router), DIRECT_FUNDING);
        s.router.directFund(s.poolId, DIRECT_FUNDING);

        s.adapter.mintRevenue(ADAPTER_FUNDING);
        s.adapter.routeRevenue(s.poolId, ADAPTER_FUNDING);
    }

    function _prepareLpWallet(uint256 lpKey, MockERC20 token0_, MockERC20 token1_) internal {
        vm.startBroadcast(lpKey);
        token0_.approve(address(permit2), type(uint256).max);
        token1_.approve(address(permit2), type(uint256).max);
        token0_.approve(address(swapRouter), type(uint256).max);
        token1_.approve(address(swapRouter), type(uint256).max);
        permit2.approve(address(token0_), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1_), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token0_), address(poolManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1_), address(poolManager), type(uint160).max, type(uint48).max);
        vm.stopBroadcast();
    }

    function _mintForLp(DemoState memory s, uint256 lpKey, address lp, uint128 liquidityAmount) internal {
        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(s.tickLower),
            TickMath.getSqrtPriceAtTick(s.tickUpper),
            liquidityAmount
        );

        vm.startBroadcast(lpKey);
        positionManager.mint(
            s.poolKey,
            s.tickLower,
            s.tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            lp,
            block.timestamp + 60,
            abi.encode(lp)
        );
        vm.stopBroadcast();
    }

    function _runSwap(DemoState memory s) internal {
        vm.startBroadcast(s.deployerKey);
        swapRouter.swapExactTokensForTokens({
            amountIn: 1 ether,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: s.poolKey,
            hookData: abi.encode(s.deployer),
            receiver: s.deployer,
            deadline: block.timestamp + 60
        });
        vm.stopBroadcast();
    }

    function _claimForLp(uint256 lpKey, IncentiveController controller_, bytes32 poolId_, address lp)
        internal
        returns (uint256 amount)
    {
        vm.startBroadcast(lpKey);
        amount = controller_.claim(poolId_, lp);
        vm.stopBroadcast();
    }
}
