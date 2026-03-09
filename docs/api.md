# API Surface

## IncentiveController

- `createProgram(PoolKey, ProgramConfig)`
- `queueProgramUpdate(bytes32 poolId, ProgramConfig)`
- `executeProgramUpdate(bytes32 poolId)`
- `rollEpoch(bytes32 poolId, uint40 startTime, uint40 endTime, uint96 emissionRate)`
- `claim(bytes32 poolId, address to)`
- `getProgramConfig(bytes32 poolId)`

## RevenueRouter

- `directFund(bytes32 poolId, uint256 amount)`
- `adapterFund(bytes32 poolId, uint256 amount)`
- `setAdapter(address adapter, bool approved)`

## RewardsVault

- `registerProgram(bytes32 poolId, ProgramConfig)`
- `updateProgramConfig(bytes32 poolId, ProgramConfig)`
- `fundProgram(bytes32 poolId, uint256 amount, address source)`
- `onLiquidityDelta(bytes32 poolId, address lp, int256 delta)`
- `claim(bytes32 poolId, address lp, address to)`
- `claimable(bytes32 poolId, address lp)`
- `getProgramState(bytes32 poolId)`
- `getUserState(bytes32 poolId, address lp)`
