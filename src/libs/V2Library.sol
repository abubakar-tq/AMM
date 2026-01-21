// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPair} from "src/interfaces/IPair.sol";

library V2Library {
    bytes32 public constant INIT_BYTECODE_HASH = 0xfa33cd26d44b535f4ac3eec567006521daa86dfa773f018387ba011fbf110101;

    error V2Library_ZeroAddress();
    error V2Library_IdenticalAddress();
    error V2Library_InsufficientLiquidity();
    error V2Library_InsufficientInputAmount();
    error V2Library_InvalidPath();

    // sortTokens
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert V2Library_IdenticalAddress();
        if (tokenA == address(0) || tokenB == address(0)) revert V2Library_ZeroAddress();

        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    // pairFor (CREATE2 address derivation)
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        bytes32 salt;
        assembly {
            mstore(0x00, token0)
            mstore(0x20, token1)
            salt := keccak256(0x00, 0x40)
        }

        bytes32 h = (keccak256(abi.encodePacked(hex"ff", factory, salt, INIT_BYTECODE_HASH)));

        pair = address(uint160(uint256(h)));
    }

    // getReserves
    function getReserves(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);

        (uint256 reserve0, uint256 reserve1,) = IPair(pairFor(factory, tokenA, tokenB)).getReserves();

        (reserveA, reserveB) = token0 == tokenA ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // Formula For price quotes
    // priceB = reserveB/reserveA (interms of A)
    // amountB = amountA * reserveB /reserveA
    // quote
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        if (amountA <= 0) revert V2Library_InsufficientInputAmount();
        if (reserveA <= 0 || reserveB <= 0) revert V2Library_InsufficientLiquidity();
        amountB = (amountA * reserveB) / reserveA;
    }

    //Derive from constant product formula
    // (x+dx)(y-dy) = xy
    // y+dy= xy/(x+dx)
    //dy= - xy/ x+dx + (y(x+dx)/x+dx)
    //dy= (-xy+xy+ydx/x+dx)
    //dy= y * dx/ (x+dx)
    // getAmountOut
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

    //Derive from constant product formula
    // (x+dx)(y-dy) = xy
    // x+dx = xy/(y-dy)
    // dx= xy/(y-dy) - x
    // dx= (xy - x(y-dy))/(y-dy)
    // dx= x * dy/(y-dy)
    //with Fee
    // dx(0.997) = x * dy/(y-dy)
    // dx = (x * dy)/(y-dy) * (1/0.997)
    // getAmountIn
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
    // getAmountsOut (multi-hop)

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

    // getAmountsIn (multi-hop)
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
