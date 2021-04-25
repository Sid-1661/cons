const { ethers } = require("hardhat");
const { getPair } = require("./init.js");
const {latest} = require("./time.js");
const BN = web3.utils.BN;

async function addLiquiEth(provider, tokenA, priceA, router, amountA = 1e8, slipper = 0.9) {
    await tokenA.connect(provider).approve(router.address, amountA);
    await router.connect(provider).addLiquidityETH(
        tokenA.address,
        amountA,
        amountA * slipper,
        priceA * amountA * slipper,
        provider.address,
        (await latest()).add(new BN(100000)).toString(), {value: priceA * amountA}
    )
}
async function addLiqui(provider, tokenA, tokenB, priceA, router, amountA = 1e8, slipper = 0.9) {
    await tokenA.connect(provider).approve(router.address, amountA);
    await tokenB.connect(provider).approve(router.address, priceA * amountA);
    await router.connect(provider).addLiquidity(
              tokenA.address,
              tokenB.address,
              amountA,
              priceA * amountA,
              amountA * slipper,
              priceA * amountA * slipper,
              provider.address,
              (await latest()).add(new BN(100000)).toString()
          );
}

async function burnLiqui(provider, tokenA, tokenB, router, remove_rate = 1, minAmount = 1e5) {
    let pair = await getPair(tokenA, tokenB)
    let balance = await pair.balanceOf(provider.address);
    await pair.connect(provider).approve(router.address, balance);
    await router.connect(provider).removeLiquidity(
              tokenA.address,
              tokenB.address,
              Math.floor(balance * remove_rate),
              minAmount,
              minAmount,
              provider.address,
              (await latest()).add(new BN(100000)).toString()
          );
}
async function burnLiquiEth(provider, tokenA, router, remove_rate = 1, minAmount = 1e5) {
    let pair = await getPair(weth, tokenA)
    let balance = await pair.balanceOf(provider.address);
    await pair.connect(provider).approve(router.address, balance);
    await router.connect(provider).removeLiquidityETH(
        tokenA.address,
        Math.floor(balance * remove_rate),
        minAmount,
        minAmount,
        provider.address,
        (await latest()).add(new BN(100000)).toString()
    )
}

async function sortTokens(tokenA, tokenB, factory) {
    let address1, address2;
    [address1, address2] = await factory.sortTokens(tokenA.address, tokenB.address);
    return [address1, address2]
}
// swap amountA tokenA for tokenB
async function swap(swapper, tokenA, tokenB, router, amountA = 1e5, slipper = 0.95) {
    // approve
    await tokenA.connect(swapper).approve(router.address, amountA)
    const Factory = await ethers.getContractFactory("CCFactory");
    let factoryAddress = await router.factory();
    let factory = await Factory.attach(factoryAddress);
    // let address1, address2;
    // [address1, address2] = await sortTokens(tokenA, tokenB, factory)
    let reserveA, reserveB;
    [reserveA, reserveB] = await factory.getReserves(tokenA.address, tokenB.address)
    let amountBMax = await router.quote(amountA, reserveA, reserveB)
    
    await router.connect(swapper).swapExactTokensForTokens(
      amountA,
      Math.floor(amountBMax * slipper),
      [tokenA.address, tokenB.address],
      swapper.address,
      (await latest()).add(new BN(100000)).toString()
    ) 
  }

  // swap amountA tokenA for tokenB
async function swapEth(swapper, weth, tokenB, router, amountEth = 1e5, slipper = 0.95) {
    const Factory = await ethers.getContractFactory("CCFactory");
    let factoryAddress = await router.factory();
    let factory = await Factory.attach(factoryAddress);

    let reserveWeth, reserveB;
    [reserveWeth, reserveB] = await factory.getReserves(weth.address, tokenB.address)
    let amountBMax = await router.quote(amountEth, reserveWeth, reserveB)
    console.log("test")
    await router.connect(swapper).swapETHForExactTokens(
      Math.floor(amountBMax * slipper),
      [weth.address, tokenB.address],
      swapper.address,
      (await latest()).add(new BN(100000)).toString(), {value: amountEth}
    ) 
  }

module.exports = {
    addLiqui,
    addLiquiEth,
    burnLiqui,
    burnLiquiEth,
    swap,
    swapEth,
    sortTokens
};