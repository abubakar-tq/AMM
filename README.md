# AMM (Uniswap V2‑style) — Foundry

Minimal constant‑product AMM implementation built with Foundry. The core includes a factory, pair (LP token), router, and library helpers.

## Contracts
- `src/Factory.sol`: creates pairs with CREATE2 and tracks pair registry.
- `src/Pair.sol`: constant‑product pool + LP token (mint, swap), flashswap callback hook, TWAP accumulators.
- `src/Router.sol`: add liquidity + swap helpers.
- `src/ERC20.sol`: internal ERC20 used for LP token.
- `src/libs/V2Library.sol`: reserve/amount math and pair address derivation.
- `src/interfaces/*`: interfaces for factory/pair/flashswap callback.

## Features
- Constant‑product swaps with fee.
- Liquidity minting (initial + proportional).
- Flashswap callback (`IV2Callee`).
- TWAP accumulators (`price0CumulativeLast`, `price1CumulativeLast`).

## Layout
```
src/
  Factory.sol
  Pair.sol
  Router.sol
  ERC20.sol
  libs/V2Library.sol
  interfaces/
    IFactory.sol
    IPair.sol
    IERC20.sol
    IV2Callee.sol
```

## Build
```bash
forge build
```

## Tests
```bash
forge test
```

## Notes
- Don't use in production! For educational/demonstration purposes only.

