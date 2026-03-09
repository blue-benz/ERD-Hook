// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IIncentiveController} from "./interfaces/IIncentiveController.sol";
import {IRewardsVault} from "./interfaces/IRewardsVault.sol";
import {IRevenueRouter} from "./interfaces/IRevenueRouter.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {Owned} from "./utils/Owned.sol";

contract RevenueRouter is IRevenueRouter, Owned {
    error AdapterNotApproved();
    error ProgramNotConfigured();

    event AdapterSet(address indexed adapter, bool approved);
    event DirectFunding(bytes32 indexed poolId, address indexed sponsor, address indexed token, uint256 amount);
    event AdapterFunding(bytes32 indexed poolId, address indexed adapter, address indexed token, uint256 amount);

    IIncentiveController public immutable controller;
    IRewardsVault public immutable rewardsVault;

    mapping(address adapter => bool approved) public approvedAdapters;

    constructor(address initialOwner, IIncentiveController controller_, IRewardsVault rewardsVault_) Owned(initialOwner) {
        controller = controller_;
        rewardsVault = rewardsVault_;
    }

    function setAdapter(address adapter, bool approved) external onlyOwner {
        approvedAdapters[adapter] = approved;
        emit AdapterSet(adapter, approved);
    }

    function directFund(bytes32 poolId, uint256 amount) external {
        address token = controller.rewardToken(poolId);
        if (token == address(0)) revert ProgramNotConfigured();

        TransferHelper.safeTransferFrom(token, msg.sender, address(rewardsVault), amount);
        rewardsVault.fundProgram(poolId, amount, msg.sender);

        emit DirectFunding(poolId, msg.sender, token, amount);
    }

    function adapterFund(bytes32 poolId, uint256 amount) external {
        if (!approvedAdapters[msg.sender]) revert AdapterNotApproved();

        address token = controller.rewardToken(poolId);
        if (token == address(0)) revert ProgramNotConfigured();

        TransferHelper.safeTransferFrom(token, msg.sender, address(rewardsVault), amount);
        rewardsVault.fundProgram(poolId, amount, msg.sender);

        emit AdapterFunding(poolId, msg.sender, token, amount);
    }
}
