// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Owned} from "../src/utils/Owned.sol";
import {ReentrancyLock} from "../src/utils/ReentrancyLock.sol";
import {TransferHelper} from "../src/libraries/TransferHelper.sol";
import {WeightingLibrary} from "../src/libraries/WeightingLibrary.sol";

contract OwnedHarness is Owned {
    constructor(address initialOwner) Owned(initialOwner) {}

    function guardedCall() external view onlyOwner returns (uint256) {
        return 1;
    }
}

contract ReentrancyHarness is ReentrancyLock {
    function enter(bool recurse) external nonReentrant returns (uint256) {
        if (recurse) this.enter(false);
        return 1;
    }
}

contract FalseReturnToken {
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

contract TransferHarness {
    function callSafeTransfer(address token, address to, uint256 amount) external {
        TransferHelper.safeTransfer(token, to, amount);
    }

    function callSafeTransferFrom(address token, address from, address to, uint256 amount) external {
        TransferHelper.safeTransferFrom(token, from, to, amount);
    }
}

contract CoverageUtilsTest is Test {
    address internal constant ALICE = address(0xA11CE);

    function testOwnedConstructorRevertsOnZeroOwner() public {
        vm.expectRevert(Owned.InvalidOwner.selector);
        new OwnedHarness(address(0));
    }

    function testOwnedTransferOwnershipLifecycle() public {
        OwnedHarness harness = new OwnedHarness(address(this));
        assertEq(harness.owner(), address(this));
        assertEq(harness.guardedCall(), 1);

        harness.transferOwnership(ALICE);
        assertEq(harness.owner(), ALICE);

        vm.expectRevert(Owned.NotOwner.selector);
        harness.transferOwnership(address(this));

        vm.expectRevert(Owned.NotOwner.selector);
        harness.guardedCall();

        vm.prank(ALICE);
        harness.transferOwnership(address(this));
        assertEq(harness.owner(), address(this));
    }

    function testOwnedTransferOwnershipRejectsZeroAddress() public {
        OwnedHarness harness = new OwnedHarness(address(this));
        vm.expectRevert(Owned.InvalidOwner.selector);
        harness.transferOwnership(address(0));
    }

    function testWeightingLibraryBranches() public {
        assertEq(WeightingLibrary.abs(5), 5);
        assertEq(WeightingLibrary.abs(-7), 7);

        (uint256 netAmount, uint256 penaltyAmount) = WeightingLibrary.applyPenalty(100, 0);
        assertEq(netAmount, 100);
        assertEq(penaltyAmount, 0);

        (netAmount, penaltyAmount) = WeightingLibrary.applyPenalty(100, 2_500);
        assertEq(netAmount, 75);
        assertEq(penaltyAmount, 25);

        assertEq(WeightingLibrary.mergeActivation(0, 11), 11);
        assertEq(WeightingLibrary.mergeActivation(20, 11), 20);
    }

    function testTransferHelperRevertsOnFalseReturn() public {
        FalseReturnToken token = new FalseReturnToken();
        TransferHarness harness = new TransferHarness();

        vm.expectRevert(TransferHelper.TransferFailed.selector);
        harness.callSafeTransfer(address(token), ALICE, 1 ether);

        vm.expectRevert(TransferHelper.TransferFromFailed.selector);
        harness.callSafeTransferFrom(address(token), address(this), ALICE, 1 ether);
    }

    function testReentrancyLockRevertsOnNestedEntry() public {
        ReentrancyHarness harness = new ReentrancyHarness();

        uint256 result = harness.enter(false);
        assertEq(result, 1);

        vm.expectRevert(ReentrancyLock.Reentrancy.selector);
        harness.enter(true);
    }
}
