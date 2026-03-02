// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {Factory} from "src/Factory.sol";
import {Router} from "src/Router.sol";
import {Pair} from "src/Pair.sol";
import {V2Library} from "src/libs/V2Library.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract RouterTest is Test {
    Factory factory;
    Router router;
    MockERC20 tokenA;
    MockERC20 tokenB;
    address feeSetter = address(0xBEEF);
    address provider = address(0xA11CE);
    address trader = address(0xB0B);

    function setUp() public {
        factory = new Factory(feeSetter);
        router = new Router(address(factory));
        tokenA = new MockERC20("TokenA", "TKA");
        tokenB = new MockERC20("TokenB", "TKB");
    }

    function _path() internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
    }

    function _addLiquidityCustom(
        MockERC20 tokenX,
        MockERC20 tokenY,
        address user,
        uint256 amountXDesired,
        uint256 amountYDesired
    ) internal returns (uint256 amountX, uint256 amountY, uint256 liquidity) {
        tokenX.mint(user, amountXDesired);
        tokenY.mint(user, amountYDesired);

        vm.startPrank(user);
        tokenX.approve(address(router), amountXDesired);
        tokenY.approve(address(router), amountYDesired);
        (amountX, amountY, liquidity) = router.addLiquidity(
            address(tokenX), address(tokenY), amountXDesired, amountYDesired, 0, 0, user, block.timestamp + 1
        );
        vm.stopPrank();
    }

    function _addLiquidity(address user, uint256 amountADesired, uint256 amountBDesired)
        internal
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        (amountA, amountB, liquidity) = _addLiquidityCustom(tokenA, tokenB, user, amountADesired, amountBDesired);
    }

    function testAddLiquidityCreatesPair() public {
        (uint256 amountA, uint256 amountB, uint256 liquidity) = _addLiquidity(provider, 10e18, 20e18);
        address pair = factory.getPair(address(tokenA), address(tokenB));

        assertTrue(pair != address(0), "pair not created");
        assertGt(liquidity, 0, "liquidity not minted");

        (uint256 reserveA, uint256 reserveB) = V2Library.getReserves(address(factory), address(tokenA), address(tokenB));
        assertEq(reserveA, amountA, "reserveA mismatch");
        assertEq(reserveB, amountB, "reserveB mismatch");
        assertEq(Pair(pair).balanceOf(provider), liquidity, "liquidity balance mismatch");
    }

    function testAddLiquidityZeroAddressReverts() public {
        vm.expectRevert(Router.Router_ZeroAddress.selector);
        router.addLiquidity(address(0), address(tokenB), 1, 1, 0, 0, provider, block.timestamp + 1);
    }

    function testAddLiquidityIdenticalAddressReverts() public {
        vm.expectRevert(Router.Router_IdenticalAddress.selector);
        router.addLiquidity(address(tokenA), address(tokenA), 1, 1, 0, 0, provider, block.timestamp + 1);
    }

    function testAddLiquidityDeadlineExpired() public {
        tokenA.mint(provider, 1e18);
        tokenB.mint(provider, 1e18);

        vm.startPrank(provider);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        vm.expectRevert(Router.Router_Expired.selector);
        router.addLiquidity(address(tokenA), address(tokenB), 1e18, 1e18, 0, 0, provider, block.timestamp - 1);
        vm.stopPrank();
    }

    function testAddLiquidityUsesOptimalAmountsFirstBranch() public {
        _addLiquidity(provider, 10e18, 5e18);

        (uint256 amountA, uint256 amountB,) = _addLiquidity(provider, 6e18, 10e18);
        uint256 expectedB = V2Library.quote(6e18, 10e18, 5e18);
        assertEq(amountA, 6e18, "amountA mismatch");
        assertEq(amountB, expectedB, "amountB mismatch");

        (uint256 reserveA, uint256 reserveB) = V2Library.getReserves(address(factory), address(tokenA), address(tokenB));
        assertEq(reserveA, 16e18, "reserveA after add mismatch");
        assertEq(reserveB, 8e18, "reserveB after add mismatch");
    }

    function testAddLiquidityUsesOptimalAmountsSecondBranch() public {
        _addLiquidity(provider, 10e18, 5e18);

        (uint256 amountA, uint256 amountB,) = _addLiquidity(provider, 5e18, 1e18);
        uint256 expectedA = V2Library.quote(1e18, 5e18, 10e18);
        assertEq(amountA, expectedA, "amountA mismatch");
        assertEq(amountB, 1e18, "amountB mismatch");

        (uint256 reserveA, uint256 reserveB) = V2Library.getReserves(address(factory), address(tokenA), address(tokenB));
        assertEq(reserveA, 12e18, "reserveA after add mismatch");
        assertEq(reserveB, 6e18, "reserveB after add mismatch");
    }

    function testAddLiquidityRevertsWhenOptimalBelowMin() public {
        _addLiquidity(provider, 10e18, 10e18);

        uint256 desiredA = 10e18;
        uint256 desiredB = 5e18;
        tokenA.mint(provider, desiredA);
        tokenB.mint(provider, desiredB);

        vm.startPrank(provider);
        tokenA.approve(address(router), desiredA);
        tokenB.approve(address(router), desiredB);
        vm.expectRevert(Router.Router_InsufficientInputAmount.selector);
        router.addLiquidity(
            address(tokenA), address(tokenB), desiredA, desiredB, 6e18, desiredB, provider, block.timestamp + 1
        );
        vm.stopPrank();
    }

    function testAddLiquiditySecondBranchRevertsWhenAmountAOptimalBelowMin() public {
        _addLiquidity(provider, 10e18, 5e18);

        vm.startPrank(provider);
        tokenA.mint(provider, 5e18);
        tokenB.mint(provider, 1e18);
        tokenA.approve(address(router), 5e18);
        tokenB.approve(address(router), 1e18);
        vm.expectRevert(Router.Router_InsufficientInputAmount.selector);
        router.addLiquidity(address(tokenA), address(tokenB), 5e18, 1e18, 3e18, 1e18, provider, block.timestamp + 1);
        vm.stopPrank();
    }

    function testSwapExactTokensForTokensSucceeds() public {
        _addLiquidity(provider, 100e18, 100e18);

        uint256 amountIn = 10e18;
        address[] memory path = _path();
        uint256[] memory quoted = V2Library.getAmountsOut(address(factory), amountIn, path);

        tokenA.mint(trader, amountIn);
        vm.startPrank(trader);
        tokenA.approve(address(router), amountIn);
        uint256[] memory amounts =
            router.swapExactTokensForTokens(amountIn, quoted[1], path, trader, block.timestamp + 1);
        vm.stopPrank();

        assertEq(amounts[1], quoted[1], "amountOut mismatch");
        assertEq(tokenB.balanceOf(trader), quoted[1], "trader output balance mismatch");
        assertEq(tokenA.balanceOf(trader), 0, "trader input not spent");

        (uint256 reserveAAfter, uint256 reserveBAfter) =
            V2Library.getReserves(address(factory), address(tokenA), address(tokenB));
        assertEq(reserveAAfter, 100e18 + amountIn, "reserveA after swap mismatch");
        assertEq(reserveBAfter, 100e18 - quoted[1], "reserveB after swap mismatch");
    }

    function testSwapExactTokensForTokensRevertsOnMinOut() public {
        _addLiquidity(provider, 50e18, 50e18);

        uint256 amountIn = 5e18;
        address[] memory path = _path();
        uint256[] memory quoted = V2Library.getAmountsOut(address(factory), amountIn, path);

        tokenA.mint(trader, amountIn);
        vm.startPrank(trader);
        tokenA.approve(address(router), amountIn);
        vm.expectRevert(Router.Router_InsufficientOutputAmount.selector);
        router.swapExactTokensForTokens(amountIn, quoted[1] + 1, path, trader, block.timestamp + 1);
        vm.stopPrank();
    }

    function testSwapExactTokensForTokensRevertsOnDeadline() public {
        _addLiquidity(provider, 50e18, 50e18);

        uint256 amountIn = 5e18;
        address[] memory path = _path();

        tokenA.mint(trader, amountIn);
        vm.startPrank(trader);
        tokenA.approve(address(router), amountIn);
        vm.expectRevert(Router.Router_Expired.selector);
        router.swapExactTokensForTokens(amountIn, 0, path, trader, block.timestamp - 1);
        vm.stopPrank();
    }

    function testSwapTokensForExactTokensSucceeds() public {
        _addLiquidity(provider, 100e18, 100e18);

        uint256 desiredOut = 10e18;
        address[] memory path = _path();
        uint256[] memory quoted = V2Library.getAmountsIn(address(factory), desiredOut, path);

        tokenA.mint(trader, quoted[0]);
        vm.startPrank(trader);
        tokenA.approve(address(router), quoted[0]);
        uint256[] memory amounts =
            router.swapTokensForExactTokens(desiredOut, quoted[0], path, trader, block.timestamp + 1);
        vm.stopPrank();

        assertEq(amounts[0], quoted[0], "amountIn mismatch");
        assertEq(tokenB.balanceOf(trader), desiredOut, "trader output balance mismatch");
        assertEq(tokenA.balanceOf(trader), 0, "trader input not spent");

        (uint256 reserveAAfter, uint256 reserveBAfter) =
            V2Library.getReserves(address(factory), address(tokenA), address(tokenB));
        assertEq(reserveAAfter, 100e18 + quoted[0], "reserveA after swap mismatch");
        assertEq(reserveBAfter, 100e18 - desiredOut, "reserveB after swap mismatch");
    }

    function testSwapTokensForExactTokensRevertsWhenMaxInTooLow() public {
        _addLiquidity(provider, 80e18, 80e18);

        uint256 desiredOut = 5e18;
        address[] memory path = _path();
        uint256[] memory quoted = V2Library.getAmountsIn(address(factory), desiredOut, path);

        tokenA.mint(trader, quoted[0]);
        vm.startPrank(trader);
        tokenA.approve(address(router), quoted[0]);
        vm.expectRevert(Router.Router_InsufficientOutputAmount.selector);
        router.swapTokensForExactTokens(desiredOut, quoted[0] - 1, path, trader, block.timestamp + 1);
        vm.stopPrank();
    }

    function testSwapTokensForExactTokensRevertsOnDeadline() public {
        _addLiquidity(provider, 50e18, 50e18);

        uint256 desiredOut = 5e18;
        address[] memory path = _path();
        uint256[] memory quoted = V2Library.getAmountsIn(address(factory), desiredOut, path);

        tokenA.mint(trader, quoted[0]);
        vm.startPrank(trader);
        tokenA.approve(address(router), quoted[0]);
        vm.expectRevert(Router.Router_Expired.selector);
        router.swapTokensForExactTokens(desiredOut, quoted[0], path, trader, block.timestamp - 1);
        vm.stopPrank();
    }

    function testSwapExactTokensForTokensMultiHop() public {
        MockERC20 tokenC = new MockERC20("TokenC", "TKC");
        _addLiquidity(provider, 100e18, 100e18);
        _addLiquidityCustom(tokenB, tokenC, provider, 100e18, 100e18);

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256 amountIn = 10e18;
        uint256[] memory quoted = V2Library.getAmountsOut(address(factory), amountIn, path);

        tokenA.mint(trader, amountIn);
        vm.startPrank(trader);
        tokenA.approve(address(router), amountIn);
        uint256[] memory amounts =
            router.swapExactTokensForTokens(amountIn, quoted[2], path, trader, block.timestamp + 1);
        vm.stopPrank();

        assertEq(amounts[2], quoted[2], "multihop amountOut mismatch");
        assertEq(tokenC.balanceOf(trader), quoted[2], "tokenC balance mismatch");
    }

    function testBurnLiquidityReturnsUnderlying() public {
        (uint256 amountAAdded, uint256 amountBAdded, uint256 liquidity) = _addLiquidity(provider, 30e18, 40e18);
        address pair = factory.getPair(address(tokenA), address(tokenB));

        (uint256 reserveABefore, uint256 reserveBBefore) =
            V2Library.getReserves(address(factory), address(tokenA), address(tokenB));

        vm.startPrank(provider);
        Pair(pair).approve(address(router), liquidity);
        (uint256 amountAOut, uint256 amountBOut) =
            router.burnLiquidity(address(tokenA), address(tokenB), liquidity, 0, 0, provider, block.timestamp + 1);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(provider), amountAOut, "tokenA out mismatch");
        assertEq(tokenB.balanceOf(provider), amountBOut, "tokenB out mismatch");
        assertGt(amountAOut, 0, "amountAOut zero");
        assertGt(amountBOut, 0, "amountBOut zero");

        (uint256 reserveAAfter, uint256 reserveBAfter) =
            V2Library.getReserves(address(factory), address(tokenA), address(tokenB));
        assertEq(reserveAAfter, reserveABefore - amountAOut, "reserveA after burn mismatch");
        assertEq(reserveBAfter, reserveBBefore - amountBOut, "reserveB after burn mismatch");
        assertEq(Pair(pair).balanceOf(provider), 0, "LP balance not burned");
        assertEq(amountAAdded - amountAOut, reserveAAfter, "tokenA locked mismatch");
        assertEq(amountBAdded - amountBOut, reserveBAfter, "tokenB locked mismatch");
    }

    function testBurnLiquidityRevertsOnMinAmounts() public {
        (uint256 amountAAdded,, uint256 liquidity) = _addLiquidity(provider, 20e18, 20e18);
        address pair = factory.getPair(address(tokenA), address(tokenB));

        vm.startPrank(provider);
        Pair(pair).approve(address(router), liquidity);
        vm.expectRevert(Router.Router_InsufficientOutputAmount.selector);
        router.burnLiquidity(
            address(tokenA), address(tokenB), liquidity, amountAAdded, 0, provider, block.timestamp + 1
        );
        vm.stopPrank();
    }

    function testBurnLiquidityRevertsOnDeadline() public {
        (,, uint256 liquidity) = _addLiquidity(provider, 20e18, 20e18);
        address pair = factory.getPair(address(tokenA), address(tokenB));

        vm.startPrank(provider);
        Pair(pair).approve(address(router), liquidity);
        vm.expectRevert(Router.Router_Expired.selector);
        router.burnLiquidity(address(tokenA), address(tokenB), liquidity, 0, 0, provider, block.timestamp - 1);
        vm.stopPrank();
    }
}
