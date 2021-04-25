const { expect } = require("chai");
const { ethers } = require("hardhat");

// const {
//     BN
//   } = require('@openzeppelin/test-helpers');

const BN = web3.utils.BN;

// my custom
const {latestBlock, advanceBlockTo, showBlock, stopAutoMine, latest} = require("./helper/time.js");
const { show } = require("./helper/meta.js");
const { mockTokenInit } = require("./helper/init.js");

describe("Chef", function() {
  let minter, alice, bob, carol;
  let ccToken, tokenA, tokenB, tokenC;
  let Chef;
  // let chef, chefRewardPerBlock, chefStartHeight, chefBonusEndHeight, bonusMultiplier;
  beforeEach(async() => {
    await stopAutoMine();
    [minter, alice, bob, carol, _] = await ethers.getSigners();
    const CCToken = await ethers.getContractFactory("CCToken");
    ccToken = await CCToken.deploy();
    Chef = await ethers.getContractFactory("MasterChef");
    [tokenA, tokenB, tokenC] = await mockTokenInit(minter, [alice, bob, carol]); // mock create token
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

  function poolInfoEqual(pooInfo, expectedInfo) {
    expect(pooInfo[0]).to.equal(expectedInfo[0]);
    expect(pooInfo[1]).to.equal(expectedInfo[1]);
    expect(pooInfo[2]).to.equal(expectedInfo[2]);
    expect(pooInfo[3]).to.equal(expectedInfo[3]);
  }


  it ("add pool should work well", async () => {
    let [chef, chefRewardPerBlock, chefStartHeight, chefBonusEndHeight, bonusMultiplier] = await initChef();
    // no info get before add pool
    expect(await chef.poolLength()).to.equal(0);
    await  expect(chef.poolInfo(0)).to.be.revertedWith("");
    // add pool 1
    let allocPoint = 100;
    await chef.add(allocPoint, tokenA.address, false);
    expect(await chef.poolLength()).to.equal(1);
    let poolInfo = await chef.poolInfo(0);
    let blockNum = await latestBlock();
    // check pool info 1
    poolInfoEqual(poolInfo, [tokenA.address, allocPoint, blockNum.toNumber(), 0]);
    // add pool 2
    let allocPoint2 = 200;
    await chef.add(allocPoint2, tokenB.address, false);
    let poolInfo2 = await chef.poolInfo(1);
    blockNum = await latestBlock();
    // check pool info 2
    poolInfoEqual(poolInfo2, [tokenB.address, allocPoint2, blockNum.toNumber(), 0]);
  })

  it('can not mine before start', async () => {
    let blockNum = await latestBlock();
    show({blockNum});
    let [chef, chefRewardPerBlock, chefStartHeight, chefBonusEndHeight, bonusMultiplier] = await initChef(80);
    await chef.add(1001, tokenA.address, false);
    await advanceBlockTo(50);
    await tokenA.connect(alice).approve(chef.address, 1000000);
    await chef.connect(alice).deposit(0, 200);
    await advanceBlockTo(60);
    expect(await chef.pendingCC(0, alice.address)).to.equal(0);
  })


  it ('can deposit before mine start, and withdraw after mine', async () => {
    let blockNum = await latestBlock();
    show({blockNum});
    [chef, chefRewardPerBlock, chefStartHeight, chefBonusEndHeight, bonusMultiplier] = await initChef(110)
    let allocPoint = 100
    await chef.add(allocPoint, tokenA.address, false);

    let aliceBeforeTokenA = await tokenA.balanceOf(alice.address);

     // deposit 
     let depositAmount = 200
     await tokenA.connect(alice).approve(chef.address, depositAmount);
     await chef.connect(alice).deposit(0, depositAmount);

     // mining
    let targetHeight = 120
    await advanceBlockTo(targetHeight);
    
    // withdraw
    let aliceInTokenA = await tokenA.balanceOf(alice.address);
    await chef.connect(alice).withdraw(0, depositAmount);
    let currentBlock = await latestBlock();
    expect(await ccToken.balanceOf(alice.address)).to.equal((currentBlock - chefStartHeight) * chefRewardPerBlock * bonusMultiplier);

    let aliceAfterTokenA = await tokenA.balanceOf(alice.address);

    expect(aliceInTokenA.add(depositAmount)).to.equal(aliceAfterTokenA);
    expect(aliceBeforeTokenA).to.equal(aliceAfterTokenA);
  })


  it('deposit after start and withdraw with no loss', async () => {
    let blockNum = await latestBlock();
    show({blockNum});
    [chef, chefRewardPerBlock, chefStartHeight, chefBonusEndHeight, bonusMultiplier] = await initChef(150);
    let startHeight = 160;
    await advanceBlockTo(startHeight);

    let allocPoint = 100;
    await chef.add(allocPoint, tokenA.address, false);

    let aliceBeforeTokenA = await tokenA.balanceOf(alice.address);

    // deposit 
    let depositAmount = 200;
    await tokenA.connect(alice).approve(chef.address, depositAmount);
    await chef.connect(alice).deposit(0, depositAmount);
    let startDepositBlock = await latestBlock();

    // mining
    let targetHeight = 180;
    await advanceBlockTo(targetHeight);
    
    // withdraw
    let aliceInTokenA = await tokenA.balanceOf(alice.address);
    await chef.connect(alice).withdraw(0, depositAmount);
    let currentBlock = await latestBlock();
    expect(await ccToken.balanceOf(alice.address)).to.equal((currentBlock - startDepositBlock) * chefRewardPerBlock * bonusMultiplier);

    let aliceAfterTokenA = await tokenA.balanceOf(alice.address);

    expect(aliceInTokenA.add(depositAmount)).to.equal(aliceAfterTokenA);
    expect(aliceBeforeTokenA).to.equal(aliceAfterTokenA);
  })

})

  





  

