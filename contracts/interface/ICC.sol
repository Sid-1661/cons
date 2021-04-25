// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICC is IERC20 {
    function mint(address to, uint256 amount) external returns (bool);
}
