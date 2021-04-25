// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface ISwapMining {
    function addVolumn(address user, address input, address output, uint256 amount) external returns (bool);
    function topUp(uint amount) external;
}
