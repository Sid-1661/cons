// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../interface/IUniswapV2Pair.sol";
import "../interface/IWETH.sol";
import "../interface/IOracle.sol";
import "../interface/IUniswapV2Factory.sol";
import "../interface/ISwapMining.sol";
import "../interface/ILottery.sol";

import "hardhat/console.sol";

contract Repurchase is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _caller;
    EnumerableSet.AddressSet private _intermediator;

    address public destroyAddress;
    address public emergencyAddress;
    address public wethAddress;
    address public targetToken;
    address public factory;
    address public lotteryAddress;
    address public swapMiningAddress;
    address public oracle;

    uint256 public constant totalAllocPoint = 1000;
    // destroyAllocPoint = totalAllocPoint.sub(lotteryAllocPoint).sub(swapMiningPoint)
    uint256 public lotteryAllocPoint;
    uint256 public swapMiningAllocPoint;

    event Burn(address pair, uint256 amount, uint amount0, uint amount1);
    event Swap(address tokenIn, address tokenOut, uint amountIn, uint amountOut);
    event Spend(uint256 lotteryAmount, uint256 swapMiningAmount, uint256 destroyAmount);
    event EmergencyWithdraw(address token, uint256 amount);


    constructor (
        address _targetToken,
        address _lotteryAddress,
        uint256 _lotteryAllocPoint,
        address _swapMiningAddress,
        uint256 _swapMiningAllocPoint,
        address _factory, 
        address _oracle, 
        address _emergencyAddress, 
        address _destroyAddress, 
        address _wethAddress) public {
        require(_targetToken != address(0), "Is zero address");
        require(_lotteryAddress != address(0), "Is zero address");
        require(_lotteryAllocPoint > 0 && _lotteryAllocPoint < totalAllocPoint, "illegal alloc point range");
        require(_swapMiningAddress != address(0), "Is zero address");
        require(_swapMiningAllocPoint > 0 && _swapMiningAllocPoint < totalAllocPoint, "illegal alloc point range");
        require(_factory != address(0), "Is zero address");
        require(_oracle != address(0), "Is zero address");
        require(_emergencyAddress != address(0), "Is zero address");
        require(_destroyAddress != address(0), "Is zero address");
        require(_wethAddress != address(0), "Is zero address");

        targetToken = _targetToken;
        lotteryAddress = _lotteryAddress;
        lotteryAllocPoint = _lotteryAllocPoint;
        swapMiningAddress = _swapMiningAddress;
        swapMiningAllocPoint = _swapMiningAllocPoint;
        factory = _factory;
        oracle = _oracle;
        emergencyAddress = _emergencyAddress;
        destroyAddress = _destroyAddress;
        wethAddress = _wethAddress;
    }
    // setter

    function setTargetToken(address _targetToken) public onlyOwner {
        require(_targetToken != address(0), "Repurchase: zero address");
        targetToken = _targetToken;
    }

    function setLotteryAddress(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "Repurchase: zero address");
        lotteryAddress = _newAddress;
    }
    
    function setLotteryAllocPoint(uint256 _lotteryAllocPoint) public onlyOwner {
        require(_lotteryAllocPoint <= totalAllocPoint, "Repurchase: lottery rate can not exceed 1");
        lotteryAllocPoint = _lotteryAllocPoint;
    }

    function setFactory(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "Repurchase: zero address");
        factory = _newAddress;
    }

    function setOracle(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "Repurchase: zero address");
        oracle = _newAddress;
    }
    
    function setEmergencyAddress(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "Repurchase: zero address");
        emergencyAddress = _newAddress;
    }

    function setDestroyAddress(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "Repurchase: zero address");
        destroyAddress = _newAddress;
    }
    // caller control part

    function addCaller(address _newCaller) public onlyOwner returns (bool) {
        require(_newCaller != address(0), "Repurchase: zero address");
        return EnumerableSet.add(_caller, _newCaller);
    }

    function delCaller(address _delCaller) public onlyOwner returns (bool) {
        require(_delCaller != address(0), "Repurchase: zero address");
        return EnumerableSet.remove(_caller, _delCaller);
    }

    function getCallerLength() public view returns (uint256) {
        return EnumerableSet.length(_caller);
    }

    function isCaller(address _call) public view returns (bool) {
        return EnumerableSet.contains(_caller, _call);
    }

    function getCaller(uint256 _index) public view returns (address){
        require(_index <= getCallerLength() - 1, "Repurchase: caller index out of bounds");
        return EnumerableSet.at(_caller, _index);
    }

    // intermediate control part

    function addIntermediator(address _addToken) public onlyOwner returns (bool) {
        require(_addToken != address(0), "Repurchase: token is the zero address");
        return EnumerableSet.add(_intermediator, _addToken);
    }

    function delIntermediator(address _delToken) public onlyOwner returns (bool) {
        require(_delToken != address(0), "Repurchase: token is the zero address");
        return EnumerableSet.remove(_intermediator, _delToken);
    }

    function getIntermediatorLength() public view returns (uint256) {
        return EnumerableSet.length(_intermediator);
    }

    function isIntermediator(address _token) public view returns (bool) {
        return EnumerableSet.contains(_intermediator, _token);
    }

    function getIntermediator(uint256 _index) public view returns (address){
        require(_index <= getIntermediatorLength() - 1, "Repurchase: index out of bounds");
        return EnumerableSet.at(_intermediator, _index);
    }

    // main function

    // ensure the pair exist before invoke this funciton
    function burn(address pair) public onlyCaller returns (bool) {
        require(pair != address(0), "Repurchase: zero pair address");
        uint256 balance = IERC20(pair).balanceOf(address(this));
        if (balance == 0) {
            return false;
        }
        // cc pair is compatible with uniswap pair 
        IUniswapV2Pair(pair).transfer(pair, balance);
        // send liquidity to pair
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(address(this));
        emit Burn(pair, balance, amount0, amount1);
        return true;
    }

    function multiBurn(address[] calldata pairs) external onlyCaller {
        uint256 length = pairs.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            burn(pairs[pid]);
        }
    }

    // show token value in anchor token
    function getTokenValue(address outputToken) public view returns (uint256) {
        uint256 outputAmount = IERC20(outputToken).balanceOf(address(this));
        uint256 quantity = 0;
        console.log("output amount: '%s'", outputAmount);
        if (outputToken == targetToken) {
            quantity = outputAmount;
            console.log("output is targetToken");
        } else if (IUniswapV2Factory(factory).getPair(outputToken, targetToken) != address(0)) {
            quantity = IOracle(oracle).consult(outputToken, outputAmount, targetToken);
            console.log("directly swap '%s'", quantity);
        } else {
            uint256 length = getIntermediatorLength();
            for (uint256 index = 0; index < length; index++) {
                address intermediate = getIntermediator(index);
                if (IUniswapV2Factory(factory).getPair(outputToken, intermediate) != address(0) && IUniswapV2Factory(factory).getPair(intermediate, targetToken) != address(0)) {
                    uint256 interQuantity = IOracle(oracle).consult(outputToken, outputAmount, intermediate);
                    quantity = IOracle(oracle).consult(intermediate, interQuantity, targetToken);
                    break;
                }
            }
        }
        return quantity;
    }


    // swap for anchor token.
    // allow swap with one intermediate
    function autoSwap(uint256 amountIn, address token) public onlyCaller returns(uint256) {
        require(token != address(0), "Repurchase: token address can not be zero");
        uint256 amountOut = 0;
        if (token == targetToken) {
            // no need to swap target token
            return 0;
        } 
        else if (IUniswapV2Factory(factory).getPair(token, targetToken) != address(0)) {
            // exist direct pair
            console.log("direct");
            amountOut = swap(amountIn, token, targetToken);
        } else {
            // check all the intermediate to see if we can swap by this intermediate
            uint256 length = getIntermediatorLength();
            for (uint256 index = 0; index < length; index++) {
                address intermediate = getIntermediator(index);
                if (IUniswapV2Factory(factory).getPair(token, intermediate) != address(0) && IUniswapV2Factory(factory).getPair(intermediate, targetToken) != address(0)) {
                    uint256 interAmount = swap(amountIn, token, intermediate);
                    amountOut = swap(interAmount, intermediate, targetToken);
                    break;
                }
            }
        }
        return amountOut;

    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'CCSwapFactory: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'CCSwapFactory: ZERO_ADDRESS');
    }
    // can only call this when pair exists
    // swap amountIn amount tokenIn to tokenOut
    function swap(uint256 amountIn, address tokenIn, address tokenOut) public returns(uint256) {
        address pair = IUniswapV2Factory(factory).getPair(tokenIn, tokenOut);
        require(pair != address(0), "Repurchase: pair not exists");
        (address token0, ) = sortTokens(tokenIn, tokenOut);            
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pair).getReserves();
        uint256 amountInWithFee = amountIn.mul(997);
        // ensure reserve1 is for tokenIn
        if (token0 != tokenOut) {
            (reserve1, reserve0) = (reserve0, reserve1);
        }
        uint256 amountOut = amountIn.mul(997).mul(reserve0) / reserve1.mul(1000).add(amountInWithFee);
        IERC20(tokenIn).safeTransfer(pair, amountIn);
        IUniswapV2Pair(pair).swap(amountOut, 0, address(this), new bytes(0));
        emit Swap(tokenIn, tokenOut, amountIn, amountOut);
        return amountOut;
    }
    function purchase(address pair) public onlyCaller {
        burn(pair);
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        autoSwap(balance0, token0);

        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        autoSwap(balance1, token1);
    }
    // burn, swap and send to spender for a series of pairs
    function pack(address[] calldata pairs) external onlyCaller {
        uint256 length = pairs.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            address pair = pairs[pid];
            purchase(pair);
        }
        toSpender();
    }

    // send current balance to lottery and destroy
    function toSpender() public  {
        uint256 balance = IERC20(targetToken).balanceOf(address(this));
        require(balance > 0, "Repurchase: balance equal 0");
        uint256 lotteryAmount = balance.mul(lotteryAllocPoint).div(totalAllocPoint);
        uint256 swapMiningAmount = balance.mul(swapMiningAllocPoint).div(totalAllocPoint);
        uint256 destroyAmount = balance.sub(lotteryAmount).sub(swapMiningAmount);
        console.log(balance);

        IERC20(targetToken).approve(lotteryAddress, lotteryAmount);
        ILottery(lotteryAddress).topUp(lotteryAmount);
        
        IERC20(targetToken).approve(swapMiningAddress, swapMiningAmount);
        ISwapMining(swapMiningAddress).topUp(swapMiningAmount);


        IERC20(targetToken).transfer(destroyAddress, destroyAmount);
        emit Spend(lotteryAmount, swapMiningAmount, destroyAmount);
    }



    modifier onlyCaller() {
        require(isCaller(msg.sender), "Repurchase: Not the caller");
        _;
    }

    function emergencyWithdraw(address token) public onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "Repurchase: Insufficient contract balance");
        IERC20(token).transfer(emergencyAddress, balance);
        emit EmergencyWithdraw(token, balance);
    }
}
