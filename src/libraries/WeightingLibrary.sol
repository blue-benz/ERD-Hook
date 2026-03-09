// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library WeightingLibrary {
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant ACC_PRECISION = 1e18;

    function abs(int256 value) internal pure returns (uint256) {
        if (value >= 0) return uint256(value);
        return uint256(-value);
    }

    function applyPenalty(uint256 amount, uint16 penaltyBps) internal pure returns (uint256 netAmount, uint256 penaltyAmount) {
        if (penaltyBps == 0 || amount == 0) return (amount, 0);
        penaltyAmount = (amount * penaltyBps) / BPS_DENOMINATOR;
        netAmount = amount - penaltyAmount;
    }

    function mergeActivation(uint40 existingActivation, uint40 nextActivation) internal pure returns (uint40 merged) {
        if (existingActivation == 0) return nextActivation;
        return existingActivation > nextActivation ? existingActivation : nextActivation;
    }
}
