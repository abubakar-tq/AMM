// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IV2Callee {
    function V2Call(address sender, uint amount0, uint amount1, bytes calldata data) external;
}
