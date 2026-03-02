// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {Factory} from "src/Factory.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Pair} from "src/Pair.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

struct SwapSnap {
    bool ok;
    uint112 r0;
    uint112 r1;
    uint256 b0After;
    uint256 b1After;
    uint256 amount0Out;
    uint256 amount1Out;
}

contract PairHandler is Test {
    Factory factory;
    Pair pair;

    MockERC20 tokenA;
    MockERC20 tokenB;

    address token0;
    address token1;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    mapping(address => bool) internal initialized;

    SwapSnap public lastSwap;

    constructor(Factory _factory, Pair _pair, MockERC20 _tokenA, MockERC20 _tokenB) {
        factory = _factory;
        pair = _pair;
        tokenA = _tokenA;
        tokenB = _tokenB;
        token0 = address(tokenA);
        token1 = address(tokenB);
    }

    function addLiquidity(uint256 seed, uint112 amount0Raw, uint112 amount1Raw) public {
        address actor = _actor(seed);
        _initActor(actor);

        IERC20 t0 = IERC20(pair.token0());
        IERC20 t1 = IERC20(pair.token1());

        (uint112 r0, uint112 r1,) = pair.getReserves();

        // fuzz one side
        uint256 amount0 = _bound(uint256(amount0Raw), 1e6, 100e18);

        uint256 amount1;
        if (r0 == 0 && r1 == 0) {
            amount1 = _bound(uint256(amount1Raw), 1e6, 100e18);
        } else {
            amount1 = (amount0 * uint256(r1)) / uint256(r0);
            if (amount1 == 0) return;
        }

        if (t0.balanceOf(actor) < amount0) return;
        if (t1.balanceOf(actor) < amount1) return;
        if (r0 + amount0 > type(uint112).max) return;
        if (r1 + amount1 > type(uint112).max) return;

        vm.startPrank(actor);
        t0.transfer(address(pair), amount0);
        t1.transfer(address(pair), amount1);
        vm.stopPrank();

        pair.mint(actor);
    }

    function removeLiquidity(uint256 seed, uint256 liquidityRaw) public {
        IERC20 lp = IERC20(address(pair));
        address actor = _actor(seed);
        uint256 balance = lp.balanceOf(actor);
        if (balance <= MINIMUM_LIQUIDITY) return;
        uint256 liquidity = _bound(liquidityRaw, MINIMUM_LIQUIDITY, balance);

        uint256 balance0;
        uint256 balance1;
        (balance0, balance1,) = pair.getReserves();
        uint256 totalSupply = lp.totalSupply();

        uint256 amount0 = (liquidity * balance0) / totalSupply;
        uint256 amount1 = (liquidity * balance1) / totalSupply;

        if (amount0 == 0 || amount1 == 0) return;

        vm.startPrank(actor);
        lp.transfer(address(pair), liquidity);
        vm.stopPrank();

        pair.burn(actor);
    }

    function swap(uint256 seed, uint112 amount0OutRaw, uint112 amount1OutRaw) public {
        IERC20 t0 = IERC20(pair.token0());
        IERC20 t1 = IERC20(pair.token1());

        (uint112 r0, uint112 r1,) = pair.getReserves();

        if (r0 == 0 || r1 == 0) return;

        uint256 amount0Out = _bound(uint256(amount0OutRaw), 0, r0 - 1);
        uint256 amount1Out = _bound(uint256(amount1OutRaw), 0, r1 - 1);

        if (amount0Out == 0 && amount1Out == 0) return;

        address actor = _actor(seed);
        _initActor(actor);

        lastSwap.ok = false;
        lastSwap.r0 = r0;
        lastSwap.r1 = r1;

        // fuzz one side
        if (amount0Out > 0) {
            uint256 amount1In = ((uint256(r1) * amount0Out * 1000) / ((uint256(r0) - amount0Out) * 997)) + 1;
            if (t1.balanceOf(actor) < amount1In) return;
            if (amount1In + r1 > type(uint112).max) return;
            lastSwap.amount0Out = amount0Out;
            lastSwap.amount1Out = 0;

            vm.startPrank(actor);
            t1.transfer(address(pair), amount1In);
            vm.stopPrank();
            pair.swap(amount0Out, 0, actor, "");
        } else {
            uint256 amount0In = ((uint256(r0) * amount1Out * 1000) / ((uint256(r1) - amount1Out) * 997)) + 1;
            if (t0.balanceOf(actor) < amount0In) return;
            if (amount0In + r0 > type(uint112).max) return;
            lastSwap.amount0Out = 0;
            lastSwap.amount1Out = amount1Out;
            vm.startPrank(actor);
            t0.transfer(address(pair), amount0In);
            vm.stopPrank();

            pair.swap(0, amount1Out, actor, "");
        }

        lastSwap.b0After = t0.balanceOf(address(pair));
        lastSwap.b1After = t1.balanceOf(address(pair));
        lastSwap.ok = true;
    }

    function _bound(uint256 x, uint256 min, uint256 max) internal pure override returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }

    function _actor(uint256 seed) internal pure returns (address a) {
        a = address(uint160(uint256(keccak256(abi.encodePacked(seed, "ACTOR")))));
    }

    function _initActor(address a) internal {
        if (initialized[a]) return;
        initialized[a] = true;

        tokenA.mint(a, 10e32);
        tokenB.mint(a, 10e32);

        vm.startPrank(a);
        tokenA.approve(address(pair), type(uint256).max);
        tokenB.approve(address(pair), type(uint256).max);
        vm.stopPrank();
    }
}
