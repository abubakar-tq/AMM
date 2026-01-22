// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {V2Library} from "src/libs/V2Library.sol";
import {IPair} from "src/interfaces/IPair.sol";
import {Pair} from "src/Pair.sol";
import {IFactory} from "src/interfaces/IFactory.sol";

contract Factory is IFactory {
    address feeReceiver;
    address feeSetter;

    mapping(address => mapping(address => address)) public getPair;

    

    address[] public allPairs;

    error Factory_IdenticalAddress();
    error Factory_ZeroAddress();
    error Factory_PairExists();
    error Factory_NotAllowed();

    constructor(address _feeSetter) {
        feeSetter = _feeSetter;
    }

    function createPair(address tokenA, address tokenB) public returns (address pair) {
        if (tokenA == tokenB) revert Factory_IdenticalAddress();
        if (tokenA == address(0) || tokenB == address(0)) revert Factory_ZeroAddress();
        if (getPair[tokenA][tokenB] != address(0)) revert Factory_PairExists();
        (address token0, address token1) = V2Library.sortTokens(tokenA, tokenB);
        bytes32 salt;
        assembly {
            mstore(0x00, token0)
            mstore(0x20, token1)
            salt := keccak256(0x00, 0x40)
        }

        bytes memory bytecode = type(Pair).creationCode;

        assembly {
            pair := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }

        IPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function allPairsLength() public view returns (uint256) {
        return allPairs.length;
    }

    function feeTo() public view returns (address) {
        return feeReceiver;
    }

    function feeToSetter() public view returns (address) {
        return feeSetter;
    }

    function setFeeTo(address _feeTo) public {
        if (msg.sender != feeSetter) {
            revert Factory_NotAllowed();
        }
        feeReceiver = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) public {
        if (msg.sender != feeSetter) {
            revert Factory_NotAllowed();
        }
        feeSetter = _feeToSetter;
    }
}
