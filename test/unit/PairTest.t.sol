// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Factory} from "src/Factory.sol";
import {V2Library} from "src/libs/V2Library.sol";
import {Test} from "forge-std/Test.sol";
import {Pair} from "src/Pair.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {FlashCallee} from "test/mocks/FlashCallee.sol";

contract PairTest is Test {
    Factory factory;
    MockERC20 tokenA;
    MockERC20 tokenB;
    Pair pair;
    address token0;
    address token1;
    address feeSetter = address(0xBEEF);
    address feeReceiver = address(0xCAFE);
    address provider = address(0xA11CE);
    address trader = address(0xB0B);

    function setUp() public {
        factory = new Factory(feeSetter);
        tokenA = new MockERC20("TokenA", "TKA");
        tokenB = new MockERC20("TokenB", "TKB");
        token0 = address(tokenA);
        token1 = address(tokenB);
        address pairAddress = factory.createPair(token0, token1);
        pair = Pair(pairAddress);
    }

    function testInitialize() public view {
        (address expected0, address expected1) = V2Library.sortTokens(token0, token1);
        assertEq(pair.token0(), expected0, "Token0 mismatch");
        assertEq(pair.token1(), expected1, "Token1 mismatch");
    }

    function testMint_FirstLiquidityUpdatesReservesAndSupply() public {
        (uint256 amount0, uint256 amount1) = (10e18, 20e18);
        _provideLiquidity(provider, amount0, amount1);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(uint256(reserve0), amount0, "reserve0 mismatch");
        assertEq(uint256(reserve1), amount1, "reserve1 mismatch");

        uint256 liquidity = pair.balanceOf(provider);
        assertGt(liquidity, 0, "liquidity should be > 0");
        assertEq(pair.totalSupply(), liquidity + pair.MINIMUM_LIQUIDITY(), "totalSupply mismatch");
    }

    function testMint_RevertInsufficientLiquidity() public {
        tokenA.mint(provider, 1);
        tokenB.mint(provider, 1);

        vm.startPrank(provider);
        tokenA.transfer(address(pair), 1);
        tokenB.transfer(address(pair), 1);
        vm.stopPrank();

        vm.expectRevert();
        vm.prank(address(factory));
        pair.mint(provider);
    }

    function testMint_SecondLiquidityMintsProportionally() public {
        _provideLiquidity(provider, 10e18, 10e18);
        (uint112 reserve0Before,,) = pair.getReserves();
        uint256 totalSupplyBefore = pair.totalSupply();

        _provideLiquidity(provider, 5e18, 5e18);

        uint256 expectedLiquidity = (5e18 * totalSupplyBefore) / uint256(reserve0Before);
        uint256 providerLiquidity = pair.balanceOf(provider);
        uint256 expectedProviderLiquidity = totalSupplyBefore - pair.MINIMUM_LIQUIDITY() + expectedLiquidity;
        assertEq(providerLiquidity, expectedProviderLiquidity, "liquidity mismatch");
    }

    function testBurn_ReturnsUnderlying() public {
        _provideLiquidity(provider, 10e18, 10e18);
        uint256 liquidity = pair.balanceOf(provider);

        vm.prank(provider);
        pair.transfer(address(pair), liquidity);

        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();
        (uint256 amount0, uint256 amount1) = pair.burn(provider);

        assertGt(amount0, 0, "amount0 should be > 0");
        assertGt(amount1, 0, "amount1 should be > 0");

        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();
        assertEq(uint256(reserve0After), uint256(reserve0Before) - amount0, "reserve0 after burn mismatch");
        assertEq(uint256(reserve1After), uint256(reserve1Before) - amount1, "reserve1 after burn mismatch");
    }

    function testBurn_RevertInsufficientLiquidityBurned() public {
        _provideLiquidity(provider, 10e18, 10e18);
        vm.expectRevert(Pair.Pair_InsufficientLiquidityBurned.selector);
        pair.burn(provider);
    }

    function testSwap_ExactIn() public {
        _provideLiquidity(provider, 100e18, 100e18);

        uint256 amountIn = 10e18;
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 amountOut = V2Library.getAmountOut(amountIn, reserve0, reserve1);

        tokenA.mint(trader, amountIn);
        vm.prank(trader);
        tokenA.transfer(address(pair), amountIn);

        vm.prank(trader);
        pair.swap(0, amountOut, trader, new bytes(0));

        assertEq(tokenB.balanceOf(trader), amountOut, "swap output mismatch");
        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();
        assertEq(uint256(reserve0After), uint256(reserve0) + amountIn, "reserve0 after swap mismatch");
        assertEq(uint256(reserve1After), uint256(reserve1) - amountOut, "reserve1 after swap mismatch");
    }

    function testSwap_FlashSwapCallback() public {
        _provideLiquidity(provider, 100e18, 100e18);

        FlashCallee callee = new FlashCallee(token0, token1, address(pair));
        tokenA.mint(address(callee), 20e18);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 amountOut = 10e18;
        uint256 amountIn = V2Library.getAmountIn(amountOut, reserve0, reserve1) + 1;

        bytes memory data = abi.encode(amountIn, uint256(0));
        pair.swap(0, amountOut, address(callee), data);

        assertEq(tokenB.balanceOf(address(callee)), amountOut, "callee should receive output");
    }

    function testSwap_RevertInsufficientOutputAmount() public {
        vm.expectRevert(Pair.Pair_InsufficientOutputAmount.selector);
        pair.swap(0, 0, provider, new bytes(0));
    }

    function testSwap_RevertInvalidTo() public {
        _provideLiquidity(provider, 10e18, 10e18);
        vm.expectRevert(Pair.Pair_InvalidTo.selector);
        pair.swap(0, 1, token0, new bytes(0));
    }

    function testSwap_RevertInsufficientLiquidity() public {
        _provideLiquidity(provider, 10e18, 10e18);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        vm.expectRevert(Pair.Pair_InsufficientLiquidity.selector);
        pair.swap(uint256(reserve0) + 1, uint256(reserve1) + 1, provider, new bytes(0));
    }

    function testSwap_RevertInsufficientInputAmount() public {
        _provideLiquidity(provider, 10e18, 10e18);
        vm.expectRevert(Pair.Pair_InsufficientInputAmount.selector);
        pair.swap(0, 1, provider, new bytes(0));
    }

    function testSkim_RemovesExcess() public {
        _provideLiquidity(provider, 10e18, 10e18);

        tokenA.mint(address(pair), 1e18);
        tokenB.mint(address(pair), 2e18);

        pair.skim(trader);

        assertEq(tokenA.balanceOf(trader), 1e18, "skim tokenA mismatch");
        assertEq(tokenB.balanceOf(trader), 2e18, "skim tokenB mismatch");
    }

    function testSync_UpdatesReserves() public {
        _provideLiquidity(provider, 10e18, 10e18);

        tokenA.mint(address(pair), 1e18);
        tokenB.mint(address(pair), 2e18);

        pair.sync();
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(uint256(reserve0), 11e18, "reserve0 after sync mismatch");
        assertEq(uint256(reserve1), 12e18, "reserve1 after sync mismatch");
    }

    function testMintFee_FeeOffClearsKLast() public {
        vm.prank(feeSetter);
        factory.setFeeTo(feeReceiver);

        _provideLiquidity(provider, 10e18, 10e18);
        assertGt(pair.kLast(), 0, "kLast should be set when fee is on");

        vm.prank(feeSetter);
        factory.setFeeTo(address(0));

        _provideLiquidity(provider, 1e18, 1e18);
        assertEq(pair.kLast(), 0, "kLast should clear when fee is off");
    }

    function testMintFee_MintsToFeeToOnGrowth() public {
        vm.prank(feeSetter);
        factory.setFeeTo(feeReceiver);

        _provideLiquidity(provider, 10e18, 10e18);

        uint256 amountIn = 1e18;
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 amountOut = V2Library.getAmountOut(amountIn, reserve0, reserve1);

        tokenA.mint(trader, amountIn);
        vm.prank(trader);
        tokenA.transfer(address(pair), amountIn);
        vm.prank(trader);
        pair.swap(0, amountOut, trader, new bytes(0));

        _provideLiquidity(provider, 10e18, 10e18);
        assertGt(pair.balanceOf(feeReceiver), 0, "feeTo should receive liquidity");
    }

    function _provideLiquidity(address to, uint256 amount0, uint256 amount1) private {
        tokenA.mint(to, amount0);
        tokenB.mint(to, amount1);

        vm.startPrank(to);
        tokenA.transfer(address(pair), amount0);
        tokenB.transfer(address(pair), amount1);
        vm.stopPrank();

        vm.prank(address(factory));
        pair.mint(to);
    }
}