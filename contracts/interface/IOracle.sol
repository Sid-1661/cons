// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

interface IOracle {
    function factory() external pure returns (address);
    function update(address tokenA, address tokenB) external returns(bool);

    function consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut);
}