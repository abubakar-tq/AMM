// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IPair} from "src/interfaces/IPair.sol";

/// @title Stateless math helpers for V2 pairs and router
/// @notice Provides deterministic pair address derivation and swap math
library V2Library {
    // keccak256(type(Pair).creationCode)
    bytes32 public constant INIT_BYTECODE_HASH = 0xbd78d9939842ea781c29e256d84172fe8a1828b98896051c5a86ab536bc0e89d;

    error V2Library_ZeroAddress();
    error V2Library_IdenticalAddress();
    error V2Library_InsufficientLiquidity();
    error V2Library_InsufficientInputAmount();
    error V2Library_InvalidPath();

    /// @notice Sort two token addresses to enforce canonical ordering
    /// @return token0 the lower address; token1 the higher address
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert V2Library_IdenticalAddress();
        if (tokenA == address(0) || tokenB == address(0)) revert V2Library_ZeroAddress();

        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /// @notice Compute pair address deterministically via CREATE2 salt
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        bytes32 h = (keccak256(abi.encodePacked(hex"ff", factory, salt, INIT_BYTECODE_HASH)));

        pair = address(uint160(uint256(h)));
    }

    /// @notice Fetch reserves for a token pair from the pair contract
    function getReserves(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);

        (uint112 reserve0, uint112 reserve1,) = IPair(pairFor(factory, tokenA, tokenB)).getReserves();

        (reserveA, reserveB) = token0 == tokenA ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // Quote formula:
    //   priceB = reserveB / reserveA (in terms of A)
    //   amountB = amountA * reserveB / reserveA

    /// @notice Given some amount of tokenA, returns equivalent amount of tokenB using reserves
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        if (amountA <= 0) revert V2Library_InsufficientInputAmount();
        if (reserveA <= 0 || reserveB <= 0) revert V2Library_InsufficientLiquidity();
        amountB = (amountA * reserveB) / reserveA;
    }

    // Derived from constant product:
    //   (x + dx)(y - dy) = xy
    //   y + dy = xy / (x + dx)
    //   dy = y * dx / (x + dx)

    /// @notice Calculates output given an input amount and reserves, after 0.3% fee
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        if (amountIn <= 0) revert V2Library_InsufficientInputAmount();
        if (reserveIn <= 0 || reserveOut <= 0) revert V2Library_InsufficientLiquidity();
        uint256 amountInAfterFee = amountIn * 997;

        amountOut = (amountInAfterFee * (reserveOut)) / ((reserveIn * 1000) + amountInAfterFee);
    }

    // Derived with fee adjustment:
    //   (x + dx)(y - dy) = xy
    //   dx = x * dy / (y - dy) adjusted by 0.997 swap fee
    //   dx_fee = dx / 0.997

    /// @notice Calculates required input to obtain a desired output after 0.3% fee
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        if (amountOut <= 0) revert V2Library_InsufficientInputAmount();
        if (reserveIn <= 0 || reserveOut <= 0) revert V2Library_InsufficientLiquidity();

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1; // +1 in favor of pair to combat rounding down errors
    }
    /// @notice Multi-hop version of getAmountOut across a path
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) revert V2Library_InvalidPath();
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i = 0; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /// @notice Multi-hop version of getAmountIn across a path
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) revert V2Library_InvalidPath();
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
