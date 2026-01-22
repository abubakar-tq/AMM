// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IPair {
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256 lastTimeStamp);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function initialize(address _token0, address _token1) external;
    function mint(address to) external returns (uint256 liquidity);
}
