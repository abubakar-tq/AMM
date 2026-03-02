# AMM Core (Foundry)

Compact constant‑product AMM in Solidity using Foundry. Architecture is compatible with Uniswap V2 semantics (CREATE2 pairs, 0.30% fee, TWAP, flash swaps) for tooling and integration familiarity.

## Modules
- `src/Factory.sol` — CREATE2 pair deployment, registry, fee configuration.
- `src/Pair.sol` — constant‑product pool + LP token (mint/burn/swap), flashswap hook, TWAP accumulators, `skim`/`sync`.
- `src/Router.sol` — liquidity entry/exit and multi‑hop swaps.
- `src/ERC20.sol` — minimal LP token with EIP‑2612 permit.
- `src/libs/V2Library.sol` — deterministic pair address + swap/quote math.
- `src/interfaces/*` — factory, pair, ERC20, and callback interfaces.

## Features
- Constant‑product swaps with 0.30% fee.
- Liquidity minting/burning (initial + proportional).
- Fee‑on minting (`feeTo`) with `kLast` tracking.
- Flashswap callback (`IV2Callee`).
- TWAP accumulators (`price0CumulativeLast`, `price1CumulativeLast`).
- `skim` and `sync` helpers.

## Layout
```
src/
  Factory.sol
  Pair.sol
  Router.sol
  ERC20.sol
  libs/
    V2Library.sol
  interfaces/
    IFactory.sol
    IPair.sol
    IERC20.sol
    IV2Callee.sol
test/
  unit/         # unit tests for factory/pair/router
  invariants/   # invariant suites
  mocks/        # mock tokens and callbacks
```

## Build & Test
```bash
forge build
forge test          # unit + invariant suites
```

## Usage
1. Deploy `Factory` with a `feeSetter`.
2. Deploy `Router` with the factory address.
3. Create a pair and add liquidity via the router.
4. Swap using `swapExactTokensForTokens` or `swapTokensForExactTokens`.

## Notes
- Fee‑on‑transfer tokens are not supported.
- Not audited; review and test before any production deployment.
