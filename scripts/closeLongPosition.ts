import {ethers} from "hardhat";
import cronosCRC20ABI from "../abis/cronosCRC20";
import priceOracleABI from "../abis/priceOracle";
import {Contract} from "ethers";

const usdcAddr = "0xc21223249CA28397B4B6541dfFaEcC539BfF0c59";
const tEthAddr = "0x543F4Db9BD26C9Eb6aD4DD1C33522c966C625774";
const priceOracleAddr = "0xD360D8cABc1b2e56eCf348BFF00D2Bd9F658754A";

// should set correct address after deployment
const traderAddr = "0x959922bE3CAee4b8Cd9a407cc3ac1C251C2007B1";

async function main() {
    console.log("=========== Close Long Position =============")
    let [user] = await ethers.getSigners();
    let trader = await ethers.getContractAt("Trader", traderAddr, user);

    const priceOracle = await ethers.getContractAt(priceOracleABI, priceOracleAddr);
    const usdc = await ethers.getContractAt(cronosCRC20ABI, usdcAddr, user);

    await usdc.approve(trader.address, ethers.constants.MaxUint256);

    const startBalance = await logBalance(usdc, user.address)
    await logPrice(priceOracle);

    console.log("> starting close long position");
    await trader.closeLongPosition(tEthAddr);
    console.log("-------- finish close long position ----------")
    const endBalance = await logBalance(usdc, user.address)

    console.log("You received: ", endBalance - startBalance);
}

async function logBalance(token: Contract, addr: string) {
    let balance = await token.balanceOf(addr);
    let decimals = await token.decimals();
    let symbol = await token.symbol();
    let amount = parseFloat(ethers.utils.formatUnits(balance, decimals));
    console.log(`${symbol} balance: ${amount}`)
    return amount;
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
