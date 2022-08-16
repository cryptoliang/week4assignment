import {ethers, network} from "hardhat";
import cronosCRC20ABI from "../abis/cronosCRC20"
import vvsRouterABI from "../abis/vvsRouter"
import {Contract} from "ethers";

const usdcAddr = "0xc21223249CA28397B4B6541dfFaEcC539BfF0c59";
const usdcOwnerAddr = "0xea01e309146551a67366fe9943E9Ed83Ae564057";
const wethAddr = "0xe44Fd7fCb2b1581822D0c862B68222998a0c299a";
const wethOwnerAddr = "0xea01e309146551a67366fe9943E9Ed83Ae564057";
const ethUsdcPairAddress = "0xfd0Cd0C651569D1e2e3c768AC0FFDAB3C8F4844f";
const vvsRouterAddress = "0x145863Eb42Cf62847A6Ca784e6416C1682b1b2Ae";
const deadline = Math.floor(Date.now() / 1000) + 180;

async function main() {
    console.log("=========== Change VVS WETH/USDC swap price =============")
    const targetUsdcPerETH = 1000;

    await network.provider.request({method: "hardhat_impersonateAccount", params: [usdcOwnerAddr]});
    await network.provider.request({method: "hardhat_impersonateAccount", params: [wethOwnerAddr]});

    let accounts = await ethers.getSigners();
    const signer = accounts[accounts.length - 1];

    let usdcOwner = await ethers.getImpersonatedSigner(usdcOwnerAddr);
    let wethOwner = await ethers.getImpersonatedSigner(wethOwnerAddr);

    const usdc = new ethers.Contract(usdcAddr, cronosCRC20ABI, usdcOwner);
    const weth = new ethers.Contract(wethAddr, cronosCRC20ABI, wethOwner);
    const vvsRouter = new ethers.Contract(vvsRouterAddress, vvsRouterABI, signer);

    weth.connect(signer).approve(vvsRouterAddress, ethers.constants.MaxUint256);
    usdc.connect(signer).approve(vvsRouterAddress, ethers.constants.MaxUint256);

    let usdcCurrent = await getAndLogBalance(usdc, ethUsdcPairAddress)
    let wethCurrent = await getAndLogBalance(weth, ethUsdcPairAddress)
    console.log("Current price USDC/WETH:", usdcCurrent / wethCurrent);

    if (Math.abs(usdcCurrent / wethCurrent - targetUsdcPerETH) < 1) {
        console.log("Current price is already the desired:", usdcCurrent / wethCurrent);
        return;
    }

    let k = usdcCurrent * wethCurrent;
    let usdcDesired = Number(Math.sqrt(k * targetUsdcPerETH).toFixed(6));
    let wethDesired = Math.sqrt(k / targetUsdcPerETH);

    if (wethDesired > wethCurrent) {
        let wethInput = ethers.utils.parseUnits((wethDesired - wethCurrent).toString(), 18);

        await weth.mint(signer.address, wethInput);
        await vvsRouter.swapExactTokensForTokens(wethInput, 0, [wethAddr, usdcAddr], signer.address, deadline);
    } else {
        let usdcSwapped = ethers.utils.parseUnits((usdcDesired - usdcCurrent).toFixed(6), 6);

        await usdc.mint(signer.address, usdcSwapped);
        await vvsRouter.swapExactTokensForTokens(usdcSwapped, 0, [usdcAddr, wethAddr], signer.address, deadline);
    }

    console.log("------ Price change finished -------");

    let usdcAmount = await getAndLogBalance(usdc, ethUsdcPairAddress)
    let wethAmount = await getAndLogBalance(weth, ethUsdcPairAddress)
    console.log("Current price USDC/WETH:", usdcAmount / wethAmount);
}

async function getBalance(token: Contract, addr: string) {
    let usdcBalance = await token.balanceOf(addr);
    let decimals = await token.decimals();
    return parseFloat(ethers.utils.formatUnits(usdcBalance, decimals));
}

async function getAndLogBalance(token: Contract, addr: string): Promise<number> {
    let amount = await getBalance(token, addr);
    let symbol = await token.symbol();
    console.log(`${symbol} balance: ${amount}`)
    return amount
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
