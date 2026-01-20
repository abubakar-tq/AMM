// Implement a minimal Pair that supports:

// swap(amount0Out, amount1Out, to, data)

// fee-adjusted invariant check (balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1000^2)

// reserve updates (_update)

// events
// mint(to) (adds liquidity, mints LP tokens)

// burn(to) (removes liquidity, burns LP tokens)

// MINIMUM_LIQUIDITY lock

// correct sqrt(x*y) logic for initial mint

// proportional mint/burn thereafter

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Pair is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address factory;
    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    error Pair_OnlyFactoryCanCall();
    error Pair_InsufficientOutputAmount();
    error Pair_InsufficientLiquidity();
    error Pair_InvalidTo();
    error Pair_InsufficientInputAmount();

    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() {
        factory = msg.sender;
    }

    modifier onlyFactory(address sender) {
        if (sender != factory) revert Pair_OnlyFactoryCanCall();
        _;
    }

    function initialize(address _token0, address _token1) external onlyFactory(msg.sender) {
        token0 = _token0;
        token1 = _token1;
    }

    // (x + x0) (y + y0)> x y
    // (x + x0 - .3(x0)) (y + y0 - .3(y0)) > x y
    // x0= x- current_balance0
    // y0= y- current_balance1

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
        if (amount0Out <= 0 && amount1Out <= 0) revert Pair_InsufficientOutputAmount();
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        if (amount0Out > _reserve0 || amount1Out > _reserve1) revert Pair_InsufficientLiquidity();
        if (to == token0 || to == token1) revert Pair_InvalidTo();
        IERC20(token0).safeTransfer(to, amount0Out);
        IERC20(token1).safeTransfer(to, amount1Out);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        if (amount0In <= 0 && amount1In <= 0) revert Pair_InsufficientInputAmount();

        uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3); // 0.003% fee
        uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);

        if (balance0Adjusted * balance1Adjusted < uint256(_reserve0) * uint256(_reserve1) * (1000 ** 2)) {
            revert Pair_InsufficientInputAmount();
        }
        _update(uint112(balance0), uint112(balance1), _reserve0, _reserve1);
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint112 balance0, uint112 balance1, uint112 _reserve0, uint112 _reserve1) private {
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        // uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        reserve0 = balance0;
        reserve1 = balance1;
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    //  Total Shares * dx/x
    function mint(address to) external returns (uint256 liquidity) {}
}
