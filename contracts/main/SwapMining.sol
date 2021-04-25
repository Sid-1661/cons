// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

import "../interface/ICCFactory.sol";
import "../interface/ICCRouter.sol";
import "../interface/IOracle.sol";
import "../interface/ISwapMining.sol";
import "hardhat/console.sol";


contract SwapMining is ISwapMining, Ownable {

    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _whitelist; // trade with token in whitelist can join swap mining
    EnumerableSet.AddressSet private _intermediator; // token in intermedator will be used for quote 
    
    address public router; // Use for add volumn only
    address public factory; // Use for volumn calculation (price quote) only, inital together with oracle
    address public oracle; // Use for volumn calculation quote (price quote) only, inital together with oracle
    address public anchorToken; // Use for volumn calculation base value

    address public rewardToken;


    uint256 public cycle; // One day usually
    uint256 public startBlock; // The start block of next cycle
    uint256 public lastCycleNum; // Last update reward cycle num
    mapping (uint256 => mapping (address => bool)) public isClaim; // The claim record of user on a certain cycle
    mapping (uint256 => mapping (address => uint256)) public cycleUserTradeVolumn; // User trade volumn in one cycle
    mapping (uint256 => uint256) public cycleTotalTradeVolumn; // Total Trade Volumn in a certain cycle

    mapping (uint256 => uint256) public cycleReward; // the amount of reward token of each cycle

    event AddVolumn(address indexed user, uint256 volumn);
    event UpdateCycleNum(address indexed user, uint256 lastCycleNum, uint256 startBlock);
    event Withdraw(address indexed user, uint256 startCycle, uint256 endCycle);
    event EmergencyWithdraw(address indexed user);
    event TopUp(address indexed user, uint amount);

    constructor(
        address _router,
        address _oracle,
        address _anchorToken,
        address _rewardToken,
        uint256 _cycle,
        uint256 _startBlock
    ) public {
        require(_router != address(0), "SwapMining: zero address");
        require(_oracle != address(0), "SwapMining: zero address");
        require(_anchorToken != address(0), "SwapMining: zero address");
        require(_rewardToken != address(0), "SwapMining: zero address");
        
        router = _router;

        oracle = _oracle;
        IOracle oracleInstance = IOracle(oracle);

        factory = oracleInstance.factory();
        require(factory != address(0), "SwapMining: zero address");

        anchorToken = _anchorToken;
        rewardToken = _rewardToken;
        cycle = _cycle;
        // init open reward time
        startBlock = _startBlock;
        // first update, nobody receive reward in the first update
        updateCycleNum();
    }

    // setter

    function setRouter(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "SwapMining: zero address");
        router = _newAddress;
    }

    function setOracle(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "SwapMining: zero address");
        oracle = _newAddress;
        // only getQuantity quote need factory and oracle, so we set it together
        IOracle oracleInstance = IOracle(oracle);
        factory = oracleInstance.factory();
        require(factory != address(0), "SwapMining: zero address");
    }


    function setAnchorToken(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "SwapMining: zero address");
        anchorToken = _newAddress;
    }

    function setRewardToken(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "SwapMining: zero address");
        rewardToken = _newAddress;
    }

    function setCycle(uint256 _cycle) public onlyOwner {
        cycle = _cycle;
    }


    // top up additioal reward to swap mining contract
    function topUp(uint256 amount) external override {
        IERC20(rewardToken).transferFrom(msg.sender, address(this), amount);
        uint256 usedCycleNum = getCurrentCycleNum();
        cycleReward[usedCycleNum] = cycleReward[usedCycleNum].add(amount);
        emit TopUp(msg.sender, amount);
    }


    // Only tokens in the whitelist can join swap mining
    function addWhitelist(address _addToken) public onlyOwner returns (bool) {
        require(_addToken != address(0), "SwapMining: token is the zero address");
        return EnumerableSet.add(_whitelist, _addToken);
    }

    function delWhitelist(address _delToken) public onlyOwner returns (bool) {
        require(_delToken != address(0), "SwapMining: token is the zero address");
        return EnumerableSet.remove(_whitelist, _delToken);
    }

    function getWhitelistLength() public view returns (uint256) {
        return EnumerableSet.length(_whitelist);
    }

    function isWhitelist(address _token) public view returns (bool) {
        return EnumerableSet.contains(_whitelist, _token);
    }

    function getWhitelist(uint256 _index) public view returns (address){
        require(_index <= getWhitelistLength() - 1, "SwapMining: index out of bounds");
        return EnumerableSet.at(_whitelist, _index);
    }

    // intermediate for quote
    function addIntermediator(address _addToken) public onlyOwner returns (bool) {
        require(_addToken != address(0), "SwapMining: token is the zero address");
        return EnumerableSet.add(_intermediator, _addToken);
    }

    function delIntermediator(address _delToken) public onlyOwner returns (bool) {
        require(_delToken != address(0), "SwapMining: token is the zero address");
        return EnumerableSet.remove(_intermediator, _delToken);
    }

    function getIntermediatorLength() public view returns (uint256) {
        return EnumerableSet.length(_intermediator);
    }

    function isIntermediator(address _token) public view returns (bool) {
        return EnumerableSet.contains(_intermediator, _token);
    }

    function getIntermediator(uint256 _index) public view returns (address){
        require(_index <= getIntermediatorLength() - 1, "SwapMining: index out of bounds");
        return EnumerableSet.at(_intermediator, _index);
    }
    
    function getQuantity(address outputToken, uint256 outputAmount) public view returns (uint256) {
        uint256 quantity = 0;
        console.log("output amount: '%s'", outputAmount);
        if (outputToken == anchorToken) {
            quantity = outputAmount;
            console.log("output is anchorToken");
        } else if (ICCFactory(factory).getPair(outputToken, anchorToken) != address(0)) {
            quantity = IOracle(oracle).consult(outputToken, outputAmount, anchorToken);
            console.log("directly swap '%s'", quantity);
        } else {
            uint256 length = getIntermediatorLength();
            for (uint256 index = 0; index < length; index++) {
                address intermediate = getIntermediator(index);
                if (ICCFactory(factory).getPair(outputToken, intermediate) != address(0) && ICCFactory(factory).getPair(intermediate, anchorToken) != address(0)) {
                    uint256 interQuantity = IOracle(oracle).consult(outputToken, outputAmount, intermediate);
                    quantity = IOracle(oracle).consult(intermediate, interQuantity, anchorToken);
                    break;
                }
            }
        }
        return quantity;
    }

    function addVolumn(address user, address input, address output, uint256 amount) external override returns (bool) {
            require(msg.sender == address(router), "SwapMining: Only Router can change user volumn");
            
            require(user != address(0), "SwapMining: Taker swap account is the zero address");
            require(input != address(0), "SwapMining: Taker swap input is the zero address");
            require(output != address(0), "SwapMining: Taker swap output is the zero address");
            // check if the token is in whitelist
            if (!isWhitelist(input) || !isWhitelist(output)) {
                return false;
            }
            console.log("in whitelist");
            uint256 quantity = getQuantity(output, amount);
            console.log("quantity : '%s'", quantity);
            if (quantity <= 0) {
                return false;
            }
            
            _addVolumn(user, quantity);

    }

    function getCurrentCycleNum() public view returns(uint256) {
         // avoid everyone wait till the no suprise end
        if (block.number >= startBlock - 10) {
            return lastCycleNum.add(1);
        } 
        return lastCycleNum;
    }


    function _addVolumn(address user, uint256 volumn) internal {
        
        uint256 usedCycleNum = getCurrentCycleNum();

        cycleUserTradeVolumn[usedCycleNum][user]
            = cycleUserTradeVolumn[usedCycleNum][user].add(volumn);
        
        cycleTotalTradeVolumn[usedCycleNum] = cycleTotalTradeVolumn[usedCycleNum].add(volumn);
        console.log("Add volumn '%s',  '%s'", msg.sender, volumn);
        emit AddVolumn(msg.sender, volumn);
    }

    // this function should be invoke periodly, or update cycle will delay
    function updateCycleNum() public returns(bool) {
        if (block.number <  startBlock) {
            console.log("no need to update");
            return false;
        }

        // volumn
        lastCycleNum = lastCycleNum.add(1);
        // update start block to next start blok height
        startBlock = block.number.add(cycle);
        emit UpdateCycleNum(msg.sender, lastCycleNum.sub(1), startBlock);
        return true;
    }
    function pending(uint256 cycleNum) public view returns (uint256) {
        if (cycleNum != 0 && !isClaim[cycleNum][msg.sender]) {
            uint256  volumn = cycleUserTradeVolumn[cycleNum][msg.sender];
                if (volumn != 0) {
                    uint256 totalVolumn = cycleTotalTradeVolumn[cycleNum];
                    if (totalVolumn != 0) {
                        // when total volumn equal 0, pending should equal 0
                        return volumn.mul(cycleReward[cycleNum]).div(totalVolumn);
                    }
                    
                }
        }
        return 0;
    }
    function withdraw(uint256 startCycle, uint256 endCycle) public {
        require(startCycle <= endCycle);
        require(endCycle <= lastCycleNum);
        uint256 reward;
        for (uint256 cycleNum = startCycle; cycleNum <= endCycle; cycleNum ++) {
            reward += pending(cycleNum);
            isClaim[cycleNum][msg.sender] = true;
        }
        IERC20(rewardToken).transfer(msg.sender, reward);
        emit Withdraw(msg.sender, startCycle, endCycle);
    }

    function emergencyWithdraw() public onlyOwner {
        IERC20(rewardToken).transfer(msg.sender, IERC20(rewardToken).balanceOf(address(this)));
        emit EmergencyWithdraw(msg.sender);
    }
}