// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Factory} from "src/Factory.sol";
import {Router} from "src/Router.sol";
import {Pair} from "src/Pair.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {RouterHandler, RouterSwapSnap} from "test/invariants/RouterHandler.t.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract RouterInvariants is StdInvariant, Test {
    Factory factory;
    Router router;
    Pair[] pairs;

    MockERC20 tokenA;
    MockERC20 tokenB;
    MockERC20 tokenC;

    RouterHandler handler;

    function setUp() public {
        tokenA = new MockERC20("A", "A");
        tokenB = new MockERC20("B", "B");
        tokenC = new MockERC20("C", "C");

        factory = new Factory(address(0xBEEF));
        router = new Router(address(factory));

        Pair[] memory ps = new Pair[](3);
        ps[0] = Pair(factory.createPair(address(tokenA), address(tokenB)));
        ps[1] = Pair(factory.createPair(address(tokenA), address(tokenC)));
        ps[2] = Pair(factory.createPair(address(tokenB), address(tokenC)));
        pairs = ps;

        handler = new RouterHandler(router, factory, ps, tokenA, tokenB, tokenC);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = RouterHandler.addLiquidity.selector;
        selectors[1] = RouterHandler.removeLiquidity.selector;
        selectors[2] = RouterHandler.swapExactTokensForTokens.selector;
        selectors[3] = RouterHandler.swapTokensForExactTokens.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_reservesMatchBalancesWhenInitialized() public view {
        for (uint256 i = 0; i < pairs.length; i++) {
            Pair p = pairs[i];
            if (p.totalSupply() > 0) {
                (uint112 r0, uint112 r1,) = p.getReserves();
                uint256 b0 = IERC20(p.token0()).balanceOf(address(p));
                uint256 b1 = IERC20(p.token1()).balanceOf(address(p));
                assertEq(uint256(r0), b0, "reserve0 != balance0");
                assertEq(uint256(r1), b1, "reserve1 != balance1");
            }
        }
    }

    function invariant_minimumLiquidityLocked() public view {
        for (uint256 i = 0; i < pairs.length; i++) {
            Pair p = pairs[i];
            uint256 ts = p.totalSupply();
            if (ts == 0) continue;
            uint256 z = p.balanceOf(address(0));
            uint256 min = p.MINIMUM_LIQUIDITY();
            assertEq(z, min, "ZERO_LP_CHANGED");
            assertGe(ts, min, "TS_BELOW_MIN");
        }
    }

    function invariant_swapFeeAdjustedK() public view {
        (
            bool ok,
            address pairAddr,
            uint112 r0_,
            uint112 r1_,
            uint256 b0,
            uint256 b1,
            uint256 amount0Out,
            uint256 amount1Out
        ) = handler.lastSwap();

        if (!ok) return;

        uint256 r0 = uint256(r0_);
        uint256 r1 = uint256(r1_);

        uint256 a0In = b0 > (r0 - amount0Out) ? b0 - (r0 - amount0Out) : 0;
        uint256 a1In = b1 > (r1 - amount1Out) ? b1 - (r1 - amount1Out) : 0;

        assertTrue(a0In > 0 || a1In > 0, "no input detected");

        uint256 b0Adj = b0 * 1000 - a0In * 3;
        uint256 b1Adj = b1 * 1000 - a1In * 3;

        assertGe(b0Adj * b1Adj, r0 * r1 * 1_000_000, "K invariant violated");
        assertTrue(pairAddr != address(0), "pair address missing");
    }

    function invariant_zeroSupplyZeroReserves() public view {
        for (uint256 i = 0; i < pairs.length; i++) {
            Pair p = pairs[i];
            if (p.totalSupply() == 0) {
                (uint112 r0, uint112 r1,) = p.getReserves();
                assertEq(r0, 0, "reserve0 non-zero with no supply");
                assertEq(r1, 0, "reserve1 non-zero with no supply");
            }
        }
    }

    function invariant_routerHoldsNoTokens() public view {
        assertEq(tokenA.balanceOf(address(router)), 0, "router holds tokenA");
        assertEq(tokenB.balanceOf(address(router)), 0, "router holds tokenB");
        assertEq(tokenC.balanceOf(address(router)), 0, "router holds tokenC");
        for (uint256 i = 0; i < pairs.length; i++) {
            assertEq(pairs[i].balanceOf(address(router)), 0, "router holds LP");
        }
    }
}
