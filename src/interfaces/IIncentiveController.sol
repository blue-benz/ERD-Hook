// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IRewardsVault} from "./IRewardsVault.sol";

interface IIncentiveController {
    function onLiquidityChanged(bytes32 poolId, address lp, int256 liquidityDelta) external;
    function onSwapObserved(bytes32 poolId, uint256 amountSpecifiedAbs) external;
    function rewardToken(bytes32 poolId) external view returns (address);
    function getProgramConfig(bytes32 poolId) external view returns (IRewardsVault.ProgramConfig memory);
}
