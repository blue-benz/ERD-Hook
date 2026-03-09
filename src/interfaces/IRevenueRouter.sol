// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IRevenueRouter {
    function adapterFund(bytes32 poolId, uint256 amount) external;
    function directFund(bytes32 poolId, uint256 amount) external;
}
