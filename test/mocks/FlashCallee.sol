// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IV2Callee} from "src/interfaces/IV2Callee.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FlashCallee is IV2Callee {
    using SafeERC20 for MockERC20;

    MockERC20 token0;
    MockERC20 token1;
    address pair;

    constructor(address _token0, address _token1, address _pair) {
        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);
        pair = _pair;
    }

    function V2Call(address, uint256 /*amount0Out*/, uint256 /*amount1Out*/, bytes calldata data) external {
        require(msg.sender == pair, "Only pair");
        (uint256 amount0In, uint256 amount1In) = abi.decode(data, (uint256, uint256));

        if (amount0In > 0) token0.safeTransfer(pair, amount0In);
        if (amount1In > 0) token1.safeTransfer(pair, amount1In);
    }
}
