// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {Router} from "src/Router.sol";
import {Factory} from "src/Factory.sol";
import {Pair} from "src/Pair.sol";
import {V2Library} from "src/libs/V2Library.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

struct RouterSwapSnap {
    bool ok;
    address pair;
    uint112 r0;
    uint112 r1;
    uint256 b0After;
    uint256 b1After;
    uint256 amount0Out;
    uint256 amount1Out;
}

contract RouterHandler is Test {
    Router router;
    Factory factory;
    Pair[] pairs; // AB, AC, BC

    MockERC20 tokenA;
    MockERC20 tokenB;
    MockERC20 tokenC;

    address token0;
    address token1;
    address token2;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    mapping(address => bool) internal initialized;

    RouterSwapSnap public lastSwap;

    constructor(
        Router _router,
        Factory _factory,
        Pair[] memory _pairs,
        MockERC20 _tokenA,
        MockERC20 _tokenB,
        MockERC20 _tokenC
    ) {
        router = _router;
        factory = _factory;
        pairs = _pairs;
        tokenA = _tokenA;
        tokenB = _tokenB;
        tokenC = _tokenC;
        token0 = address(tokenA);
        token1 = address(tokenB);
        token2 = address(tokenC);
    }

    function addLiquidity(uint256 seed, uint112 amount0DesiredRaw, uint112 amount1DesiredRaw) public {
        uint256 pairIndex = uint256(seed % pairs.length);
        (bool ok, uint256 amount0, uint256 amount1) =
            _prepareAddLiquidity(pairIndex, amount0DesiredRaw, amount1DesiredRaw);
        if (!ok) return;

        address actor = _actor(seed);
        _initActor(actor);
        (address t0, address t1) = (pairs[pairIndex].token0(), pairs[pairIndex].token1());

        vm.prank(actor);
        try router.addLiquidity(t0, t1, amount0, amount1, 0, 0, actor, block.timestamp + 1) {}
        catch {
            return;
        }
    }

    function removeLiquidity(uint256 seed, uint256 liquidityRaw) public {
        uint256 pairIndex = uint256(seed % pairs.length);
        Pair p = pairs[pairIndex];
        address actor = _actor(seed);
        _initActor(actor);

        uint256 balance = IERC20(address(p)).balanceOf(actor);
        if (balance <= MINIMUM_LIQUIDITY) return;

        uint256 liquidity = _bound(liquidityRaw, MINIMUM_LIQUIDITY, balance);

        uint256 ts = p.totalSupply();
        if (ts == 0) return;
        (uint112 r0, uint112 r1,) = p.getReserves();

        uint256 amount0 = (liquidity * uint256(r0)) / ts;
        uint256 amount1 = (liquidity * uint256(r1)) / ts;
        if (amount0 == 0 || amount1 == 0) return;

        vm.startPrank(actor);
        IERC20(address(p)).approve(address(router), liquidity);
        try router.burnLiquidity(p.token0(), p.token1(), liquidity, 0, 0, actor, block.timestamp + 1) {}
        catch {
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
    }

    function swapExactTokensForTokens(uint256 seed, uint112 amountInRaw) public {
        (address[] memory path, Pair lastPair) = _buildPath(seed);
        if (path.length < 2) return;
        if (!_hasLiquidity(path)) return;

        uint256 amountIn = _bound(uint256(amountInRaw), 1e6, 50e18);

        address actor = _actor(seed);
        _initActor(actor);
        if (IERC20(path[0]).balanceOf(actor) < amountIn) return;

        (bool amountsOk, uint256[] memory amounts) = _safeGetAmountsOut(amountIn, path);
        if (!amountsOk || amounts[amounts.length - 1] == 0) return;

        (uint112 r0, uint112 r1,) = lastPair.getReserves();
        lastSwap.ok = false;
        lastSwap.pair = address(lastPair);
        lastSwap.r0 = r0;
        lastSwap.r1 = r1;

        bool inputIsToken0 = path[path.length - 2] == lastPair.token0();
        lastSwap.amount0Out = inputIsToken0 ? 0 : amounts[amounts.length - 1];
        lastSwap.amount1Out = inputIsToken0 ? amounts[amounts.length - 1] : 0;

        vm.prank(actor);
        try router.swapExactTokensForTokens(amountIn, 0, path, actor, block.timestamp + 1) {}
        catch {
            return;
        }

        lastSwap.b0After = IERC20(lastPair.token0()).balanceOf(address(lastPair));
        lastSwap.b1After = IERC20(lastPair.token1()).balanceOf(address(lastPair));
        lastSwap.ok = true;
    }

    function swapTokensForExactTokens(uint256 seed, uint112 amountOutRaw) public {
        (address[] memory path, Pair lastPair) = _buildPath(seed);
        if (path.length < 2) return;
        if (!_hasLiquidity(path)) return;

        (uint112 r0, uint112 r1,) = lastPair.getReserves();
        uint256 reserveOut = path[path.length - 1] == lastPair.token0() ? uint256(r0) : uint256(r1);
        if (reserveOut <= 1) return;

        uint256 amountOut = _bound(uint256(amountOutRaw), 1, reserveOut - 1);

        (bool amountsOk, uint256[] memory amounts) = _safeGetAmountsIn(amountOut, path);
        if (!amountsOk) return;
        uint256 amountInMax = (amounts[0] * 11) / 10 + 1;

        address actor = _actor(seed);
        _initActor(actor);
        if (IERC20(path[0]).balanceOf(actor) < amountInMax) return;

        lastSwap.ok = false;
        lastSwap.pair = address(lastPair);
        lastSwap.r0 = r0;
        lastSwap.r1 = r1;
        bool outputIsToken0 = path[path.length - 1] == lastPair.token0();
        lastSwap.amount0Out = outputIsToken0 ? amountOut : 0;
        lastSwap.amount1Out = outputIsToken0 ? 0 : amountOut;

        vm.prank(actor);
        try router.swapTokensForExactTokens(amountOut, amountInMax, path, actor, block.timestamp + 1) {}
        catch {
            return;
        }

        lastSwap.b0After = IERC20(lastPair.token0()).balanceOf(address(lastPair));
        lastSwap.b1After = IERC20(lastPair.token1()).balanceOf(address(lastPair));
        lastSwap.ok = true;
    }

    function _bound(uint256 x, uint256 min, uint256 max) internal pure override returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }

    function _actor(uint256 seed) internal pure returns (address a) {
        a = address(uint160(uint256(keccak256(abi.encodePacked(seed, "ROUTER_ACTOR")))));
    }

    function _initActor(address a) internal {
        if (initialized[a]) return;
        initialized[a] = true;

        tokenA.mint(a, 10e32);
        tokenB.mint(a, 10e32);
        tokenC.mint(a, 10e32);

        vm.startPrank(a);
        IERC20(token0).approve(address(router), type(uint256).max);
        IERC20(token1).approve(address(router), type(uint256).max);
        IERC20(token2).approve(address(router), type(uint256).max);
        for (uint256 i = 0; i < pairs.length; i++) {
            IERC20(address(pairs[i])).approve(address(router), type(uint256).max);
        }
        vm.stopPrank();
    }

    function _prepareAddLiquidity(uint256 pairIndex, uint112 amount0DesiredRaw, uint112 amount1DesiredRaw)
        internal
        view
        returns (bool ok, uint256 amount0, uint256 amount1)
    {
        amount0 = _bound(uint256(amount0DesiredRaw), 1e6, 100e18);
        amount1 = _bound(uint256(amount1DesiredRaw), 1e6, 100e18);

        Pair p = pairs[pairIndex];
        (uint112 r0, uint112 r1,) = p.getReserves();

        uint256 reserve0 = uint256(r0);
        uint256 reserve1 = uint256(r1);
        if (!(r0 == 0 && r1 == 0)) {
            uint256 temp = V2Library.quote(amount0, reserve0, reserve1);
            if (temp == 0) return (false, amount0, amount1);
            if (temp > amount1) {
                temp = V2Library.quote(amount1, reserve1, reserve0);
                if (temp == 0) return (false, amount0, amount1);
                amount0 = temp;
            } else {
                amount1 = temp;
            }
        }

        if (reserve0 + amount0 > type(uint112).max) return (false, amount0, amount1);
        if (reserve1 + amount1 > type(uint112).max) return (false, amount0, amount1);

        uint256 ts = p.totalSupply();
        if (ts == 0) {
            if (amount0 * amount1 <= MINIMUM_LIQUIDITY * MINIMUM_LIQUIDITY) return (false, amount0, amount1);
        } else {
            if ((amount0 * ts) / reserve0 == 0) return (false, amount0, amount1);
            if ((amount1 * ts) / reserve1 == 0) return (false, amount0, amount1);
        }

        ok = true;
    }

    function _buildPath(uint256 seed) internal view returns (address[] memory path, Pair lastPair) {
        bool twoHop = (seed >> 8) & 1 == 1;
        if (!twoHop) {
            uint256 pairIndex = uint256(seed % pairs.length);
            Pair p = pairs[pairIndex];
            path = new address[](2);
            bool reverse = (seed >> 9) & 1 == 1;
            if (reverse) {
                path[0] = p.token1();
                path[1] = p.token0();
            } else {
                path[0] = p.token0();
                path[1] = p.token1();
            }
            lastPair = p;
            return (path, lastPair);
        }

        uint256 route = uint256(seed % 6);
        path = new address[](3);
        if (route == 0) {
            path[0] = token0; // A->B->C
            path[1] = token1;
            path[2] = token2;
        } else if (route == 1) {
            path[0] = token0; // A->C->B
            path[1] = token2;
            path[2] = token1;
        } else if (route == 2) {
            path[0] = token1; // B->A->C
            path[1] = token0;
            path[2] = token2;
        } else if (route == 3) {
            path[0] = token1; // B->C->A
            path[1] = token2;
            path[2] = token0;
        } else if (route == 4) {
            path[0] = token2; // C->A->B
            path[1] = token0;
            path[2] = token1;
        } else {
            path[0] = token2; // C->B->A
            path[1] = token1;
            path[2] = token0;
        }

        lastPair = _pairFor(path[1], path[2]);
    }

    function _pairFor(address a, address b) internal view returns (Pair p) {
        address addr = factory.getPair(a, b);
        if (addr != address(0)) p = Pair(addr);
    }

    function _hasLiquidity(address[] memory path) internal view returns (bool) {
        for (uint256 i = 0; i < path.length - 1; i++) {
            Pair p = _pairFor(path[i], path[i + 1]);
            if (address(p) == address(0)) return false;
            (uint112 r0, uint112 r1,) = p.getReserves();
            if (r0 == 0 || r1 == 0) return false;
        }
        return true;
    }

    function _getAmountsOut(uint256 amountIn, address[] memory path) external view returns (uint256[] memory) {
        return V2Library.getAmountsOut(address(factory), amountIn, path);
    }

    function _getAmountsIn(uint256 amountOut, address[] memory path) external view returns (uint256[] memory) {
        return V2Library.getAmountsIn(address(factory), amountOut, path);
    }

    function _safeGetAmountsOut(uint256 amountIn, address[] memory path)
        internal
        view
        returns (bool ok, uint256[] memory amounts)
    {
        try this._getAmountsOut(amountIn, path) returns (uint256[] memory amts) {
            return (true, amts);
        } catch {
            return (false, amounts);
        }
    }

    function _safeGetAmountsIn(uint256 amountOut, address[] memory path)
        internal
        view
        returns (bool ok, uint256[] memory amounts)
    {
        try this._getAmountsIn(amountOut, path) returns (uint256[] memory amts) {
            return (true, amts);
        } catch {
            return (false, amounts);
        }
    }
}
