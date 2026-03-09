// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IRevenueRouter} from "../interfaces/IRevenueRouter.sol";
import {Owned} from "../utils/Owned.sol";

interface IMintableERC20 {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract MockRevenueAdapter is Owned {
    event RevenueMinted(uint256 amount);
    event RevenueRouted(bytes32 indexed poolId, uint256 amount);

    IMintableERC20 public immutable rewardToken;
    IRevenueRouter public immutable router;

    constructor(address initialOwner, IMintableERC20 rewardToken_, IRevenueRouter router_) Owned(initialOwner) {
        rewardToken = rewardToken_;
        router = router_;
    }

    function mintRevenue(uint256 amount) external onlyOwner {
        rewardToken.mint(address(this), amount);
        emit RevenueMinted(amount);
    }

    function routeRevenue(bytes32 poolId, uint256 amount) external onlyOwner {
        rewardToken.approve(address(router), amount);
        router.adapterFund(poolId, amount);
        emit RevenueRouted(poolId, amount);
    }
}
