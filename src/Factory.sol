// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {V2Library} from "src/libs/V2Library.sol";
import {IPair} from "src/interfaces/IPair.sol";
import {Pair} from "src/Pair.sol";
import {IFactory} from "src/interfaces/IFactory.sol";

/// @title Pair factory for the constant-product AMM
/// @notice Deploys Pair contracts using CREATE2 and tracks fee configuration
/// @dev Mirrors Uniswap V2 factory surface with simplified fee toggles
contract Factory is IFactory {
    address feeReceiver;
    address feeSetter;

    mapping(address => mapping(address => address)) public getPair;

    address[] public allPairs;

    error Factory_IdenticalAddress();
    error Factory_ZeroAddress();
    error Factory_PairExists();
    error Factory_NotAllowed();

    /// @param _feeSetter address allowed to configure fee receivers
    constructor(address _feeSetter) {
        feeSetter = _feeSetter;
    }

    /// @notice Create a new pair for tokenA and tokenB if it does not exist
    /// @param tokenA first token address
    /// @param tokenB second token address
    /// @return pair deployed pair address
    function createPair(address tokenA, address tokenB) public returns (address pair) {
        if (tokenA == tokenB) revert Factory_IdenticalAddress();
        if (tokenA == address(0) || tokenB == address(0)) revert Factory_ZeroAddress();
        if (getPair[tokenA][tokenB] != address(0)) revert Factory_PairExists();
        (address token0, address token1) = V2Library.sortTokens(tokenA, tokenB);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

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

    /// @notice Total number of pairs created by the factory
    function allPairsLength() public view returns (uint256) {
        return allPairs.length;
    }

    /// @notice Current address receiving protocol fees
    function feeTo() public view returns (address) {
        return feeReceiver;
    }

    /// @notice Address allowed to update fee configuration
    function feeToSetter() public view returns (address) {
        return feeSetter;
    }

    /// @notice Set the protocol fee receiver
    /// @param _feeTo new fee receiver; zero address disables fee minting
    function setFeeTo(address _feeTo) public {
        if (msg.sender != feeSetter) {
            revert Factory_NotAllowed();
        }
        feeReceiver = _feeTo;
    }

    /// @notice Transfer fee-setter role to a new address
    /// @param _feeToSetter new fee setter
    function setFeeToSetter(address _feeToSetter) public {
        if (msg.sender != feeSetter) {
            revert Factory_NotAllowed();
        }
        feeSetter = _feeToSetter;
    }
}
