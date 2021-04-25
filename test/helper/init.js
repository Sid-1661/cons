const BN = web3.utils.BN;

async function initCCToken() {
    const CCToken = await ethers.getContractFactory("CCToken");
    ccToken = await CCToken.deploy();
    return ccToken
}

async function initCCFactory(minter) {
    // factory
    const Factory = await ethers.getContractFactory("CCFactory");
    // set feeTo setter to minter
    factory = await Factory.deploy(minter.address)

    // oracle
    const Oracle = await ethers.getContractFactory("Oracle");
    oracle = await Oracle.deploy(factory.address)
    return [factory, oracle]
}

async function initWETH() {
    // @Notice Mock WETH, will be replaced in formal deploy
    const WETH = await ethers.getContractFactory("WETH9");
    weth = await WETH.deploy()
    return weth;
}

async function initRouter(factory, weth) {
    const Rounter = await ethers.getContractFactory("CCRouter");
    router = await Rounter.deploy(factory.address, weth.address)
    return router
}

async function initBlackHole() {
    const BlackHole = await ethers.getContractFactory("BlackHole");
    let blockHole = await BlackHole.deploy()
    return blockHole;
}

async function initLottery(router, oracle, weth, ccToken, cycleNum = 100, startBlock = 200) {
    const Lottery = await ethers.getContractFactory("Lottery");

    let lottery = await Lottery.deploy(
        router.address, 
        oracle.address,
        weth.address, 
        ccToken.address,
        cycleNum,
        startBlock
        )
    return lottery;
}

async function initSawpMining(router, oracle, weth, ccToken, cycleNum = 100, startBlock = 100) {
    const SwapMining = await ethers.getContractFactory("SwapMining");

    swapMining = await SwapMining.deploy(
        router.address, 
        oracle.address,
        weth.address,
        ccToken.address,
        cycleNum,
        startBlock
        )
    return swapMining;
}

async function initRepurchase(ccToken, lottery, swapMining, factory, oracle, blockHole, weth, emergencyAccount, lotteryAllocPoint = 200, swapMiningAllocPoint = 400) {
    const Repurchase = await ethers.getContractFactory("Repurchase")
    repurchase =  await Repurchase.deploy(ccToken.address,
        lottery.address,
        lotteryAllocPoint,
        swapMining.address,
        swapMiningAllocPoint,
        factory.address, oracle.address, emergencyAccount.address, blockHole.address,  weth.address)
    return repurchase;
}

async function initAll(minter) {
    // mock weth
    let weth = await initWETH()
    // project main cc token
    let ccToken = await initCCToken()
    // build factory and oracle
    let [factory, oracle] = await initCCFactory(minter)
    // build router binded with factory and weth
    let router = await initRouter(factory, weth);
    // set oracle address so that everytime add liquidity the oracle can have chance to update
    await router.setOracle(oracle.address);

     // build lottery
     let lottery = await initLottery(router, oracle, weth, ccToken)
     // set lottery
     await router.setLottery(lottery.address)

      // build swap mining
      let swapMining = await initSawpMining(router, oracle, weth, ccToken)
      // set swap mining
      await router.setSwapMining(swapMining.address)
    
    // init black hole so that repurchase can destroy
    let blackHole = await initBlackHole();
    // init repurchase 
    let repurchase = await initRepurchase(ccToken, lottery, swapMining, factory, oracle, blackHole, weth, minter)
    // add minter as a caller of repurchase
    await repurchase.addCaller(minter.address)

    // set factory fee rate
    await factory.setFeeToRate(5);
    // set factory fee to 
    await factory.setFeeTo(repurchase.address);
    return [weth, ccToken, factory, oracle, router, lottery, swapMining, blackHole, repurchase]
}
// use pair for to get pair address, this pair may not exist yet
async function getPair(tokenA, tokenB) {
    let pairAddress = await router.pairFor(tokenA.address, tokenB.address)
    Pair = await ethers.getContractFactory("CCPair");
    let pair = await Pair.attach(pairAddress);
    return pair;
}

async function getTestToken(address) {

    let TestToken = await  ethers.getContractFactory("TestToken");
    let token = await TestToken.attach(address);
    return token;
}
const INIT_AMOUNT = "10000000000000000000000"
async function mockTokenInit(minter, users, mockNum = 3, initAmount = INIT_AMOUNT) {
    // Mock Tokens
    TestToken = await ethers.getContractFactory("TestToken");
    let tokens = []
    for (let index = 0; index < mockNum; index++) {
        tokens.push(await TestToken.deploy())
    }
   
    // transfer Mock Tokens to users
    tokens.forEach(async (token) => {
        users.forEach(async (user) => {
            await token.connect(minter).transfer(user.address, initAmount)
        });
    });
    return tokens;
}

module.exports = {
    mockTokenInit,
    initCCToken,
    initCCFactory,
    initWETH,
    initAll,
    getPair,
    getTestToken
};