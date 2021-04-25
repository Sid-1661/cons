const { expect } = require("chai");
const { ethers } = require("hardhat");
const {BN} = require('@openzeppelin/test-helpers');
// my custom
const {latestBlock, advanceBlockTo, showBlock, stopAutoMine} = require("./helper/time.js");
const { show } = require("./helper/meta.js");
const {addLiqui, addLiquiEth, burnLiqui, burnLiquiEth, swap, swapEth} = require("./helper/swapHelper.js")
const {mockUniswap, mockPairs} = require('./helper/mockUniswap.js')
const { mockTokenInit } = require("./helper/init.js");

describe("Chef", function() {
  
  let ccToken, chef, weth, factory, oracle, router, uniswapRouter;
  let minter, alice, bob, carol;
  let Chef;
  let tokenA, tokenB, tokenC;
  
  beforeEach(async() => {
    await stopAutoMine();
    [minter, alice, bob, carol, _] = await ethers.getSigners();

    const CCToken = await ethers.getContractFactory("CCToken");
    ccToken = await CCToken.deploy();
    Chef = await ethers.getContractFactory("MasterChef");

    const Factory = await ethers.getContractFactory("CCFactory");
    // set feeTo setter to minter
    factory = await Factory.deploy(minter.address)

    const Oracle = await ethers.getContractFactory("Oracle");
    oracle = await Oracle.deploy(factory.address)

    // @Notice Mock WETH, will be replaced in formal deploy
    const WETH = await ethers.getContractFactory("WETH9");
    weth = await WETH.deploy()

    const Rounter = await ethers.getContractFactory("CCRouter");
    router = await Rounter.deploy(factory.address, weth.address);

    // mock create token
    [tokenA, tokenB, tokenC] = await mockTokenInit(minter, [alice, bob, carol]);

    // mock Uniswap
    let result =  await mockUniswap(minter, weth)
    uniswapRouter = result[0]
    uniFactory = result[1]
    const targetTokens = [{address: tokenA.address, price: 100, artifact: tokenA},
       {address: tokenB.address, price: 200, artifact: tokenB},
      {address: tokenC.address, price: 400, artifact: tokenC}]
    await mockPairs(uniswapRouter, uniFactory, weth, alice, targetTokens)
  });

  async function initChef(chefStartHeight = -1, bonusPeriod = 100, chefRewardPerBlock = 100) {
    if (chefStartHeight == -1) {
      chefStartHeight = (await latestBlock()).toNumber();
    }
    chefBonusEndHeight = chefStartHeight + bonusPeriod
    chef = await Chef.deploy(ccToken.address, chefRewardPerBlock, chefStartHeight, chefBonusEndHeight);
    bonusMultiplier = await chef.BONUS_MULTIPLIER()
    // Add chef to minter chef can mint
    await ccToken.addMinter(chef.address);
    return [chef, chefRewardPerBlock, chefStartHeight, chefBonusEndHeight, bonusMultiplier]
  }

  it ('chef deposit lp and withdraw immediately', async() => {
    let [chef, chefRewardPerBlock, chefStartHeight, chefBonusEndHeight, bonusMultiplier] = await initChef();

    let balance0 = await ccToken.balanceOf(alice.address)
      await chef.add(100, tokenA.address, false)
      await tokenA.connect(alice).approve(chef.address, 1000000);
      await chef.connect(alice).deposit(0, 100)
      let depositBlockNum = await latestBlock()

      await chef.connect(alice).withdraw(0, 100)

      let withdrawBlockNum = await latestBlock()
      let balance1 = await ccToken.balanceOf(alice.address)
      expect(balance1).to.equal(balance0 + (withdrawBlockNum - depositBlockNum) * chefRewardPerBlock * bonusMultiplier);

  })

  it ('chef deposit lp', async() => {
    let [chef, chefRewardPerBlock, chefStartHeight, chefBonusEndHeight, bonusMultiplier] = await initChef();
    let balance0 = await ccToken.balanceOf(alice.address)
      await chef.add(100, tokenA.address, true)
      await tokenA.connect(alice).approve(chef.address, 1000000);
      await chef.connect(alice).deposit(0, 100)
      let depositBlockNum = await latestBlock()
      await advanceBlockTo(151)
      await chef.connect(alice).withdraw(0, 100)
      let withdrawBlockNum = await latestBlock()
      let balance1 = await ccToken.balanceOf(alice.address)
      let reward =  (withdrawBlockNum - depositBlockNum) * chefRewardPerBlock * bonusMultiplier;
      let expectBalance = new BN(balance0.toString()).add(new BN(reward))
      expect(balance1).to.equal(expectBalance.toString());
  })

  it ('chef deposit lp and withdraw 0', async() => {
    let [chef, chefRewardPerBlock, chefStartHeight, chefBonusEndHeight, bonusMultiplier] = await initChef();
    
      let balance0 = await ccToken.balanceOf(alice.address);
      await chef.add(100, tokenA.address, true);
      await tokenA.connect(alice).approve(chef.address, 1000000);
      await chef.connect(alice).deposit(0, 100);
      let depositBlockNum = await latestBlock();
      await advanceBlockTo(200);
      await chef.connect(alice).withdraw(0, 0);
      let withdrawBlockNum = await latestBlock();
      let reward =  (withdrawBlockNum - depositBlockNum) * chefRewardPerBlock * bonusMultiplier;
      expect(await ccToken.balanceOf(alice.address)).to.equal(balance0.add(reward));

      await advanceBlockTo(250)
      balance0 = await ccToken.balanceOf(alice.address);
      await chef.connect(alice).withdraw(0, 0);
      let newWithdrawBlockNum = await latestBlock();
      reward =  (newWithdrawBlockNum - withdrawBlockNum) * chefRewardPerBlock * bonusMultiplier;
      expect(await ccToken.balanceOf(alice.address)).to.equal(balance0.add(reward));
      let lastWithdrawBlockNum = newWithdrawBlockNum;

      // cross bonus end block
      await advanceBlockTo(300);
      balance0 = await ccToken.balanceOf(alice.address);
      await chef.connect(alice).withdraw(0, 0);
      newWithdrawBlockNum = await latestBlock();
      let bonusEndBlock = (await chef.bonusEndBlock()).toNumber();
      beforeBonusReward = (bonusEndBlock - lastWithdrawBlockNum) * chefRewardPerBlock * bonusMultiplier;
      afterBounusReward = (newWithdrawBlockNum - bonusEndBlock) * chefRewardPerBlock
      reward =  beforeBonusReward + afterBounusReward;
      expect(await ccToken.balanceOf(alice.address)).to.equal(balance0.add(reward));
      lastWithdrawBlockNum = newWithdrawBlockNum;

      // after bonus end block
      await advanceBlockTo(350);
      balance0 = await ccToken.balanceOf(alice.address);
      await chef.connect(alice).withdraw(0, 0);
      newWithdrawBlockNum = await latestBlock();
      afterBounusReward = (newWithdrawBlockNum - lastWithdrawBlockNum) * chefRewardPerBlock
      expect(await ccToken.balanceOf(alice.address)).to.equal(balance0.add(afterBounusReward));
  })
});
