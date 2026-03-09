# Security

## Controls Implemented

- Pool-manager-only hook entrypoints via `BaseHook`.
- Controller accepts accounting updates only from configured hook.
- Config updates are delay-gated (`queueProgramUpdate` / `executeProgramUpdate`).
- Reentrancy guard on claim path.
- No unbounded loops in distribution/claim flows.

## Attack Surface and Mitigations

- Flash in/out liquidity farming:
  - Warm-up gating and cooldown penalties.
- Double-claim attempts:
  - Reward debt + pending accounting reset on claim.
- Unauthorized funding/config:
  - owner/adapter checks and token-bound routing.
- Hook misuse:
  - hook permission bits and strict callback source checks.

## Residual Risks

- Admin key risk (owner can create/update programs).
- LP sybil fragmentation is not eliminated by on-chain accounting alone.
- HookData LP attribution must be respected by integrated periphery UX.

No claims of attack-proofness are made.
