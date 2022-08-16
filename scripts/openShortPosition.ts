import {ethers} from "hardhat";
import cronosCRC20ABI from "../abis/cronosCRC20";
import tTokenABI from "../abis/tToken";
import priceOracleABI from "../abis/priceOracle";
import {Contract} from "ethers";

const usdcAddr = "0xc21223249CA28397B4B6541dfFaEcC539BfF0c59";
const tUsdcAddr = "0xB3bbf1bE947b245Aef26e3B6a9D777d7703F4c8e";
const tEthAddr = "0x543F4Db9BD26C9Eb6aD4DD1C33522c966C625774";
const priceOracleAddr = "0xD360D8cABc1b2e56eCf348BFF00D2Bd9F658754A";

// should set correct address after deployment
const traderAddr = "0x959922bE3CAee4b8Cd9a407cc3ac1C251C2007B1";

async function main() {
    console.log("=========== Open Short Position =============")
    let [user] = await ethers.getSigners();
    let trader = await ethers.getContractAt("Trader", traderAddr, user);

    const priceOracle = await ethers.getContractAt(priceOracleABI, priceOracleAddr);
    const usdc = await ethers.getContractAt(cronosCRC20ABI, usdcAddr, user);
    const tUsdc = await ethers.getContractAt(tTokenABI, tUsdcAddr, user);
    const tEth = await ethers.getContractAt(tTokenABI, tEthAddr, user);

    await usdc.approve(trader.address, ethers.constants.MaxUint256);

    await logBalance(usdc, user.address)
    await logPrice(priceOracle);

    console.log("> starting open short position");
    let usdcAmount = ethers.utils.parseUnits("1000", 6);

    await trader.short(usdcAmount, tEthAddr, 3)

    console.log("-------- finish open short position ----------")
    await logBalance(usdc, user.address)
    await logUnderlying(tUsdc, trader.address, "USDC", 6);
    await logBorrow(tEth, trader.address, "WETH", 18);
}

async function logBalance(token: Contract, addr: string) {
    let balance = await token.balanceOf(addr);
    let decimals = await token.decimals();
    let symbol = await token.symbol();
    let amount = parseFloat(ethers.utils.formatUnits(balance, decimals));
    console.log(`${symbol} balance: ${amount}`)
}

async function logUnderlying(tToken: Contract, addr: string, symbol: string, decimals: number) {
    let balance = await tToken.callStatic.balanceOfUnderlying(addr);
    let amount = parseFloat(ethers.utils.formatUnits(balance, decimals));
    console.log(`${symbol} collateral balance: ${amount}`)
}

async function logBorrow(tToken: Contract, addr: string, symbol: string, decimals: number) {
    let balance = await tToken.callStatic.borrowBalanceCurrent(addr);
    let amount = parseFloat(ethers.utils.formatUnits(balance, decimals));
    console.log(`${symbol} borrow balance: ${amount}`)
}

async function logPrice(priceOracle: Contract) {
    let ethPriceBefore = await priceOracle.getUnderlyingPrice(tEthAddr);
    console.log("USD/ETH price:", ethers.utils.formatUnits(ethPriceBefore, 18));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
