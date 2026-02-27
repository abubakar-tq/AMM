// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

interface IPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 lastTimeStamp);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function initialize(address _token0, address _token1) external;
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
}
