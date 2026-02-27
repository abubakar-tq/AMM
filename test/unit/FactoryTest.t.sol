// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IPair} from "src/interfaces/IPair.sol";
import {Factory} from "src/Factory.sol";
import {Pair} from "src/Pair.sol";
import {Test} from "forge-std/Test.sol";
import {V2Library} from "src/libs/V2Library.sol";

event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

contract FactoryTest is Test {
    Factory factory;
    address feeSetter = address(0xBEEF);
    address feeReceiver = address(0xCAFE);

    function setUp() public {
        factory = new Factory(feeSetter);
    }

    function testCreatePair() public {
        address tokenA = address(0x1111);
        address tokenB = address(0x2222);

        address pair = factory.createPair(tokenA, tokenB);

        address getPairAddress = factory.getPair(tokenA, tokenB);
        assertEq(pair, getPairAddress, "Pair address mismatch");

        uint256 allPairsLength = factory.allPairsLength();
        assertEq(allPairsLength, 1, "All pairs length should be 1");
    }

    function testCreatePair_SymmetricGetPair() public {
        address tokenA = address(0x1111);
        address tokenB = address(0x2222);

        address pair = factory.createPair(tokenA, tokenB);
        assertEq(factory.getPair(tokenB, tokenA), pair, "getPair should be symmetric");
    }

    function testCreatePair_AllPairsLengthMultiple() public {
        factory.createPair(address(0x1111), address(0x2222));
        factory.createPair(address(0x3333), address(0x4444));

        assertEq(factory.allPairsLength(), 2, "All pairs length should be 2");
    }

    function testCreatePair_IdenticalAddress() public {
        address tokenA = address(0x1111);
        vm.expectRevert(Factory.Factory_IdenticalAddress.selector);
        factory.createPair(tokenA, tokenA);
    }

    function testCreatePair_ZeroAddress() public {
        address tokenA = address(0x1111);
        address tokenB = address(0x0);
        vm.expectRevert(Factory.Factory_ZeroAddress.selector);
        factory.createPair(tokenA, tokenB);
    }

    function testCreatePair_PairExists() public {
        address tokenA = address(0x1111);
        address tokenB = address(0x2222);
        factory.createPair(tokenA, tokenB);
        vm.expectRevert(Factory.Factory_PairExists.selector);
        factory.createPair(tokenA, tokenB);
    }

    function testPairAddressMatch_V2Library() public {
        address tokenA = address(0x1111);
        address tokenB = address(0x2222);
        address pairFromFactory = factory.createPair(tokenA, tokenB);
        address pairFromLibrary = V2Library.pairFor(address(factory), tokenA, tokenB);
        assertEq(pairFromFactory, pairFromLibrary, "Pair address from factory and library do not match");
    }

    function testCreatePair_EmitEvent() public {
        address tokenA = address(0x1111);
        address tokenB = address(0x2222);
        address expectedPair = V2Library.pairFor(address(factory), tokenA, tokenB);
        vm.expectEmit(true, true, true, true);
        emit PairCreated(tokenA, tokenB, expectedPair, 1);
        factory.createPair(tokenA, tokenB);
    }

    function testSetFeeTo() public {
        vm.prank(feeSetter);
        factory.setFeeTo(feeReceiver);
        address currentFeeTo = factory.feeTo();
        assertEq(currentFeeTo, feeReceiver, "FeeTo address mismatch");
    }

    function testSetFeeTo_NotAllowed() public {
        address notFeeSetter = address(0xDEAD);
        vm.prank(notFeeSetter);
        vm.expectRevert(Factory.Factory_NotAllowed.selector);
        factory.setFeeTo(feeReceiver);
    }

    function testConstructor_FeeSetter() public view {
        address currentFeeSetter = factory.feeToSetter();
        assertEq(currentFeeSetter, feeSetter, "FeeSetter address mismatch");
    }

    function testPairInitializedCorrectly() public {
        address tokenA = address(0x1111);
        address tokenB = address(0x2222);
        address pairAddress = factory.createPair(tokenA, tokenB);
        IPair pair = IPair(pairAddress);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(reserve0, 0, "Initial reserve0 should be 0");
        assertEq(reserve1, 0, "Initial reserve1 should be 0");
    }

    function testPairInitialize_RevertIfNonFactory() public {
        address pairAddress = factory.createPair(address(0x1111), address(0x2222));
        IPair pair = IPair(pairAddress);

        vm.prank(address(0xDEAD));
        vm.expectRevert(Pair.Pair_OnlyFactoryCanCall.selector);
        pair.initialize(address(0x1111), address(0x2222));
    }

    function testPairInitialize_RevertIfAlreadyInitialized() public {
        address pairAddress = factory.createPair(address(0x1111), address(0x2222));
        IPair pair = IPair(pairAddress);

        vm.prank(address(factory));
        vm.expectRevert(Pair.Pair_AlreadyInitialized.selector);
        pair.initialize(address(0x1111), address(0x2222));
    }

    function testFeeSetterCanBeChangedByFeeSetter() public {
        address newFeeSetter = address(0xB0B0);
        vm.prank(feeSetter);
        factory.setFeeToSetter(newFeeSetter);
        address currentFeeSetter = factory.feeToSetter();
        assertEq(currentFeeSetter, newFeeSetter, "FeeSetter address mismatch after change");
    }

    function testSetFeeSetter_NotAllowed() public {
        address notFeeSetter = address(0xDEAD);
        vm.prank(notFeeSetter);
        vm.expectRevert(Factory.Factory_NotAllowed.selector);
        factory.setFeeToSetter(address(0xB0B0));
    }
}
