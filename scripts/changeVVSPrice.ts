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

async function main() {
    console.log("=========== Change VVS WETH/USDC swap price =============")
    const targetUsdcPerETH = 1000;
    const isAddLiquidity = false;

    await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [usdcOwnerAddr],
    });

    await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [wethOwnerAddr],
    });

    let accounts = await ethers.getSigners();
    const signer = accounts[accounts.length - 1];

    let usdcOwner = await ethers.getImpersonatedSigner(usdcOwnerAddr);
    let wethOwner = await ethers.getImpersonatedSigner(wethOwnerAddr);

    const usdc = new ethers.Contract(usdcAddr, cronosCRC20ABI, usdcOwner);
    const weth = new ethers.Contract(wethAddr, cronosCRC20ABI, wethOwner);
    const vvsRouter = new ethers.Contract(vvsRouterAddress, vvsRouterABI, signer);

    let usdcCurrent = await getAndLogBalance(usdc, ethUsdcPairAddress, "USDC", 6)
    let wethCurrent = await getAndLogBalance(weth, ethUsdcPairAddress, "WETH", 18)
    console.log("Current price USDC/WETH:", usdcCurrent / wethCurrent);


    if (Math.abs(usdcCurrent / wethCurrent - targetUsdcPerETH) < 1) {
        console.log("Current price is already the desired:", usdcCurrent / wethCurrent);
        return;
    }

    let k = usdcCurrent * wethCurrent;
    let usdcDesired = Number(Math.sqrt(k * targetUsdcPerETH).toFixed(6));
    let wethDesired = Math.sqrt(k / targetUsdcPerETH);
    // console.log("USDC Desired :", usdcDesired)
    // console.log("WETH Desired :", wethDesired)

    let deadline = Math.floor(Date.now() / 1000) + 180;


    if (wethDesired > wethCurrent) {
        let wethInput = ethers.utils.parseUnits((wethDesired - wethCurrent).toString(), 18);

        await weth.mint(signer.address, wethInput);
        await weth.connect(signer).approve(vvsRouterAddress, wethInput);
        await vvsRouter.swapExactTokensForTokens(wethInput, 0, [wethAddr, usdcAddr], signer.address, deadline);
    } else {
        let usdcSwapped = ethers.utils.parseUnits((usdcDesired - usdcCurrent).toFixed(6), 6);

        await usdc.mint(signer.address, usdcSwapped);
        await usdc.connect(signer).approve(vvsRouterAddress, usdcSwapped);
        await vvsRouter.swapExactTokensForTokens(usdcSwapped, 0, [usdcAddr, wethAddr], signer.address, deadline);
    }

    console.log("------ Price change finished -------");

    let usdcAmount = await getAndLogBalance(usdc, ethUsdcPairAddress, "USDC", 6)
    let wethAmount = await getAndLogBalance(weth, ethUsdcPairAddress, "WETH", 18)
    console.log("Current price USDC/WETH:", usdcAmount / wethAmount);

    if (isAddLiquidity) {
        console.log("---------- add liquidity ------------");
        let wethAdd = ethers.utils.parseUnits("100", 18);
        let usdcAdd = ethers.utils.parseUnits((100 * targetUsdcPerETH).toFixed(6), 6);
        weth.connect(signer).approve(vvsRouterAddress, wethAdd);
        usdc.connect(signer).approve(vvsRouterAddress, usdcAdd);
        await weth.mint(signer.address, wethAdd);
        await usdc.mint(signer.address, usdcAdd);
        await vvsRouter.addLiquidity(usdcAddr, wethAddr, usdcAdd, wethAdd, 0, 0, signer.address, deadline);

        usdcAmount = await getAndLogBalance(usdc, ethUsdcPairAddress, "USDC", 6)
        wethAmount = await getAndLogBalance(weth, ethUsdcPairAddress, "WETH", 18)
        console.log("Current price USDC/WETH:", usdcAmount / wethAmount);
    }
}

async function getAndLogBalance(token: Contract, addr: string, symbol: string, decimals: number): Promise<number> {
    let usdcBalance = await token.balanceOf(addr);
    let amount = parseFloat(ethers.utils.formatUnits(usdcBalance, decimals));
    console.log(`${symbol} balance: ${amount}`)
    return amount
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
