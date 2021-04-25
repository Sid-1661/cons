// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../interface/IUniswapV2Pair.sol";
import "../interface/ICCFactory.sol";
import "../interface/ICCPair.sol";

contract Migrator {
    address public chef;
    address public oldFactory;
    ICCFactory public factory;
    uint256 public notBeforeBlock;
    uint256 public desiredLiquidity = uint256(-1);

    constructor(
        address _chef,
        address _oldFactory,
        ICCFactory _factory,
        uint256 _notBeforeBlock
    ) public {
        chef = _chef;
        oldFactory = _oldFactory;
        factory = _factory;
        notBeforeBlock = _notBeforeBlock;
    }

    function migrate(IUniswapV2Pair orig) public returns (ICCPair) {
        require(msg.sender == chef, "Migrator: not from master chef");
        require(block.number >= notBeforeBlock, "Migrator: too early to migrate");
        require(orig.factory() == oldFactory, "Migrator: not from old factory");
        address token0 = orig.token0();
        address token1 = orig.token1();
        ICCPair pair = ICCPair(factory.getPair(token0, token1));
        if (pair == ICCPair(address(0))) {
            pair = ICCPair(factory.createPair(token0, token1));
        }
        uint256 lp = orig.balanceOf(msg.sender);
        if (lp == 0) return pair;
        desiredLiquidity = lp;
        orig.transferFrom(msg.sender, address(orig), lp);
        orig.burn(address(pair));
        pair.mint(msg.sender);
        desiredLiquidity = uint256(-1);
        return pair;
    }
}