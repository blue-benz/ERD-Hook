// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {IIncentiveController} from "./interfaces/IIncentiveController.sol";
import {WeightingLibrary} from "./libraries/WeightingLibrary.sol";

contract IncentivesHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    error InvalidHookData();

    event LiquidityObserved(bytes32 indexed poolId, address indexed lp, int256 liquidityDelta);
    event SwapObserved(bytes32 indexed poolId, uint256 amountSpecifiedAbs, bool zeroForOne);

    IIncentiveController public immutable controller;

    mapping(bytes32 poolId => uint256 swaps) public beforeSwapCount;
    mapping(bytes32 poolId => uint256 swaps) public afterSwapCount;

    constructor(IPoolManager poolManager_, IIncentiveController controller_) BaseHook(poolManager_) {
        controller = controller_;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeAddLiquidity(address, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4)
    {
        address lp = _decodeLp(hookData);
        bytes32 poolId = PoolId.unwrap(key.toId());

        controller.onLiquidityChanged(poolId, lp, params.liquidityDelta);

        emit LiquidityObserved(poolId, lp, params.liquidityDelta);
        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        address lp = _decodeLp(hookData);
        bytes32 poolId = PoolId.unwrap(key.toId());

        controller.onLiquidityChanged(poolId, lp, params.liquidityDelta);

        emit LiquidityObserved(poolId, lp, params.liquidityDelta);
        return BaseHook.beforeRemoveLiquidity.selector;
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        bytes32 poolId = PoolId.unwrap(key.toId());
        uint256 volume = WeightingLibrary.abs(params.amountSpecified);

        beforeSwapCount[poolId] += 1;

        controller.onSwapObserved(poolId, volume);
        emit SwapObserved(poolId, volume, params.zeroForOne);

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        bytes32 poolId = PoolId.unwrap(key.toId());
        afterSwapCount[poolId] += 1;

        return (BaseHook.afterSwap.selector, 0);
    }

    function _decodeLp(bytes calldata hookData) internal pure returns (address lp) {
        if (hookData.length != 32) revert InvalidHookData();
        lp = abi.decode(hookData, (address));
        if (lp == address(0)) revert InvalidHookData();
    }
}
