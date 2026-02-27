// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {V2Library} from "src/libs/V2Library.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPair} from "src/interfaces/IPair.sol";
import {IFactory} from "src/interfaces/IFactory.sol";

contract Router {
    address public immutable FACTORY;

    using SafeERC20 for IERC20;

    error Router_Expired();
    error Router_InsufficientOutputAmount();
    error Router_ZeroAddress();
    error Router_IdenticalAddress();
    error Router_InsufficientInputAmount();

    modifier ensure(uint256 deadline) {
        _ensure(deadline);
        _;
    }

    function _ensure(uint256 deadline) internal view {
        if (deadline < block.timestamp) revert Router_Expired();
    }

    constructor(address _factory) {
        FACTORY = _factory;
    }

    // swapExactTokensForTokens
    // Get total amounts
    //Send tokens to first Pair
    //Call internal swap which iterates over the whole path
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = V2Library.getAmountsOut(FACTORY, amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) {
            revert Router_InsufficientOutputAmount();
        }

        // Transfer tokens from sender to the first pair
        IERC20(path[0]).safeTransferFrom(msg.sender, V2Library.pairFor(FACTORY, path[0], path[1]), amounts[0]);

        _swap(amounts, path, to);
    }

    function _swap(uint256[] memory amounts, address[] memory path, address _to) private {
        for (uint256 i = 0; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = V2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? V2Library.pairFor(FACTORY, output, path[i + 2]) : _to;
            IPair(V2Library.pairFor(FACTORY, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    // swapTokensForExactTokens
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = V2Library.getAmountsIn(FACTORY, amountOut, path);
        if (amounts[0] > amountInMax) {
            revert Router_InsufficientOutputAmount();
        }

        // Transfer tokens from sender to the first pair
        IERC20(path[0]).safeTransferFrom(msg.sender, V2Library.pairFor(FACTORY, path[0], path[1]), amounts[0]);

        _swap(amounts, path, to);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);

        IERC20(tokenA).safeTransferFrom(msg.sender, V2Library.pairFor(FACTORY, tokenA, tokenB), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, V2Library.pairFor(FACTORY, tokenA, tokenB), amountB);

        liquidity = IPair(V2Library.pairFor(FACTORY, tokenA, tokenB)).mint(to);
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) private returns (uint256 amountA, uint256 amountB) {
        if (tokenA == address(0) || tokenB == address(0)) {
            revert Router_ZeroAddress();
        }
        if (tokenA == tokenB) {
            revert Router_IdenticalAddress();
        }
        if (IFactory(FACTORY).getPair(tokenA, tokenB) == address(0)) {
            IFactory(FACTORY).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = V2Library.getReserves(FACTORY, tokenA, tokenB);

        if (reserveA == 0 && reserveB == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            uint256 amountBOptimal = V2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) {
                    revert Router_InsufficientInputAmount();
                }
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint256 amountAOptimal = V2Library.quote(amountBDesired, reserveB, reserveA);
                if (amountAOptimal < amountAMin) {
                    revert Router_InsufficientInputAmount();
                }
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
        }
    }

    function burnLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = V2Library.pairFor(FACTORY, tokenA, tokenB);

        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);

        (uint256 amount0, uint256 amount1) = IPair(pair).burn(to);

        (address token0,) = V2Library.sortTokens(tokenA, tokenB);

        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);

        if (amountA < amountAMin) {
            revert Router_InsufficientOutputAmount();
        }
        if (amountB < amountBMin) {
            revert Router_InsufficientOutputAmount();
        }
    }
}
