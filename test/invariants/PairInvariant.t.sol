// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {Factory} from "src/Factory.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {FlashCallee} from "test/mocks/FlashCallee.sol";
import {Pair} from "src/Pair.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Router} from "src/Router.sol";
import {PairHandler} from "test/invariants/PairHandler.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {SwapSnap} from "test/invariants/PairHandler.t.sol";

contract PairInvariants is StdInvariant, Test {
    Factory factory;
    Pair pair;

    MockERC20 tokenA;
    MockERC20 tokenB;

    PairHandler handler;

    function setUp() public {
        tokenA = new MockERC20("A", "A");
        tokenB = new MockERC20("B", "B");

        factory = new Factory(address(0xBEEF));
        pair = Pair(factory.createPair(address(tokenA), address(tokenB)));

        handler = new PairHandler(factory, pair, tokenA, tokenB);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = PairHandler.addLiquidity.selector;
        selectors[1] = PairHandler.removeLiquidity.selector;
        selectors[2] = PairHandler.swap.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    //After any pair interaction, But in case of donations in between it won't hold but for our handler it must always hold because we are not allowing donations in handler and also we are not fuzzing with donation scenario
    function invariant_reservesMatchBalancesWhenInitialized() public view {
        (uint112 r0, uint112 r1,) = pair.getReserves();

        if (pair.totalSupply() > 0) {
            uint256 b0 = IERC20(pair.token0()).balanceOf(address(pair));
            uint256 b1 = IERC20(pair.token1()).balanceOf(address(pair));

            assertEq(uint256(r0), b0, "reserve0 != balance0");
            assertEq(uint256(r1), b1, "reserve1 != balance1");
        }
    }

    function invariant_minimumLiquidityLocked() public view {
        uint256 ts = pair.totalSupply();
        if (ts == 0) return;

        uint256 z = pair.balanceOf(address(0));
        uint256 min = pair.MINIMUM_LIQUIDITY();

        assertEq(z, min, "ZERO_LP_CHANGED");
        assertGe(ts, min, "TS_BELOW_MIN");
    }

    function invariant_swapFeeAdjustedK() public view {
        (bool ok, uint112 r0_, uint112 r1_, uint256 b0, uint256 b1, uint256 amount0Out, uint256 amount1Out) =
            handler.lastSwap();

        if (!ok) return;

        uint256 r0 = uint256(r0_);
        uint256 r1 = uint256(r1_);

        uint256 a0In = b0 > (r0 - amount0Out) ? b0 - (r0 - amount0Out) : 0;
        uint256 a1In = b1 > (r1 - amount1Out) ? b1 - (r1 - amount1Out) : 0;

        assertTrue(a0In > 0 || a1In > 0, "no input detected");

        uint256 b0Adj = b0 * 1000 - a0In * 3;
        uint256 b1Adj = b1 * 1000 - a1In * 3;

        assertGe(b0Adj * b1Adj, r0 * r1 * 1_000_000, "K invariant violated");
    }

    function invariant_zeroSupplyZeroReserves() public view {
        if (pair.totalSupply() == 0) {
            (uint112 r0, uint112 r1,) = pair.getReserves();
            assertEq(r0, 0, "reserve0 non-zero with no supply");
            assertEq(r1, 0, "reserve1 non-zero with no supply");
        }
    }
}
