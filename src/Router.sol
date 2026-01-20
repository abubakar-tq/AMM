// addLiquidity

// removeLiquidity

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {V2Library} from "src/libs/V2Library.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPair} from "src/interfaces/IPair.sol";

contract Router {
    address public immutable FACTORY;

    using SafeERC20 for IERC20;

    error Router_Expired();
    error Router_InsufficientOutputAmount();

    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) revert Router_Expired();
        _;
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
}
