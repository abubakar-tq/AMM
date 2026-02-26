# AMM (Uniswap V2‑style) — Foundry

Educational, minimal constant‑product AMM implemented in Solidity using Foundry. Includes core contracts (factory, pair/LP token, router) plus helper math and interfaces.

## Contracts
- `src/Factory.sol`: creates pairs via CREATE2 and stores pair registry + fee configuration.
- `src/Pair.sol`: constant‑product pool + LP token (mint, burn, swap), flashswap callback, TWAP accumulators, `skim`/`sync`.
- `src/Router.sol`: add liquidity + swap helpers.
- `src/ERC20.sol`: LP token implementation (EIP‑2612 permit).
- `src/libs/V2Library.sol`: reserve/amount math and deterministic pair address derivation.
- `src/interfaces/*`: interfaces for factory/pair/callback.

## Features
- Constant‑product swaps with 0.30% fee.
- Liquidity minting/burning (initial + proportional).
- Fee‑on minting (`feeTo`) and `kLast` tracking.
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
  libs/V2Library.sol
  interfaces/
    IFactory.sol
    IPair.sol
    IERC20.sol
    IV2Callee.sol
test/
  unit/
  mocks/
```

## Setup
```bash
forge install
forge build
```

## Tests
```bash
forge test
```

## Coverage
```bash
forge coverage
```

## Usage (Local)
1. Deploy `Factory` with a `feeSetter`.
2. Deploy `Router` pointing to the factory.
3. Create a pair and add liquidity via the router.

## Security
- This code is for learning and local experimentation only.
- Not audited; do not use in production.

## Notes
- Fee‑on‑transfer tokens are not supported by the router.

