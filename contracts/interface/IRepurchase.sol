// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IRepurchase {
    function repurchase(address pairAddress, uint256 liquidity) external;
}