import {ethers, network} from "hardhat";
import cronosOracleABI from "../abis/cronosOracle"
import priceOracleABI from "../abis/priceOracle";

const usdEthPriceOracleAddr = "0x6850A6e773b9a625C6810E34070491d0FF97E065";
const usdEthPriceOracleOwnerAddr = "0x71F0cDb17454ad7EeB7e26242292fe0E0189645a";
const priceOracleAddr = "0xD360D8cABc1b2e56eCf348BFF00D2Bd9F658754A";
const tEthAddr = "0x543F4Db9BD26C9Eb6aD4DD1C33522c966C625774";

async function main() {
    console.log("=========== Change USD/ETH Oracle price =============")
    const price = 1000_00000000;

    await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [usdEthPriceOracleOwnerAddr],
    });

    let owner = await ethers.getImpersonatedSigner(usdEthPriceOracleOwnerAddr);

    const cronosOracle = new ethers.Contract(usdEthPriceOracleAddr, cronosOracleABI, owner);
    const priceOracle = await ethers.getContractAt(priceOracleABI, priceOracleAddr);

    const timestamp = Math.floor(Date.now() / 1000);
    const roundId = timestamp * 100000;

    let ethPriceBefore = await priceOracle.getUnderlyingPrice(tEthAddr);
    console.log("USD/ETH price before:", ethers.utils.formatUnits(ethPriceBefore, 18));

    await cronosOracle.updatePrice(roundId, timestamp, price);

    let etherPriceAfter = await priceOracle.getUnderlyingPrice(tEthAddr);
    console.log("USD/ETH price after:", ethers.utils.formatUnits(etherPriceAfter, 18));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
