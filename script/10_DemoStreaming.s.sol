// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IRewardsVault} from "../src/interfaces/IRewardsVault.sol";
import {ERDDemoBase} from "./base/ERDDemoBase.s.sol";

contract DemoStreamingScript is ERDDemoBase {
    function run() external {
        _runDemo(IRewardsVault.DistributionType.STREAMING);
    }
}
