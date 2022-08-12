import {ethers} from "hardhat";
import cronosCRC20ABI from "../abis/cronosCRC20";
import tTokenABI from "../abis/tToken";
import priceOracleABI from "../abis/priceOracle";
import {Contract} from "ethers";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";

const usdcAddress = "0xc21223249CA28397B4B6541dfFaEcC539BfF0c59";
const tUsdcAddress = "0xB3bbf1bE947b245Aef26e3B6a9D777d7703F4c8e";
const tEthAddress = "0x543F4Db9BD26C9Eb6aD4DD1C33522c966C625774";
const priceOracleAddress = "0xD360D8cABc1b2e56eCf348BFF00D2Bd9F658754A";


describe("Trader", async () => {
    async function deployFixture() {
        const TraderFactory = await ethers.getContractFactory("Trader");
        const trader = await TraderFactory.deploy();
        return {trader};
    }

    let priceOracle: Contract, tETHContract: Contract, tUsdcContract: Contract, usdcContract: Contract,
        accounts: SignerWithAddress[];

    beforeEach(async () => {
        accounts = await ethers.getSigners();
        usdcContract = await ethers.getContractAt(cronosCRC20ABI, usdcAddress, accounts[0]);
        tUsdcContract = await ethers.getContractAt(tTokenABI, tUsdcAddress, accounts[0]);
        tETHContract = await ethers.getContractAt(tTokenABI, tEthAddress);
        priceOracle = await ethers.getContractAt(priceOracleABI, priceOracleAddress);
    });

    it("should short and close position", async () => {
        console.log("ETH price", await priceOracle.getUnderlyingPrice(tEthAddress));
        let {trader} = await deployFixture();
        await usdcContract.approve(trader.address, ethers.utils.parseUnits("10000000000", 6));

        console.log("USDC balance before short", await usdcContract.balanceOf(accounts[0].address));
        await trader.short(ethers.utils.parseUnits("1000", 6), tEthAddress)
        console.log("USDC balance after short", await usdcContract.balanceOf(accounts[0].address));
        console.log("tUSDC balance after short", await tUsdcContract.balanceOf(trader.address));
        console.log("borrowed ETH after short", await tETHContract.callStatic.borrowBalanceCurrent(trader.address));
        console.log("USDC needed to close position", await trader.callStatic.getClosePositionAmount(tEthAddress));

        await trader.closePosition(tEthAddress);
        console.log("USDC balance after close position", await usdcContract.balanceOf(accounts[0].address));
        console.log("tUSDC balance after close position", await tUsdcContract.balanceOf(trader.address));
        console.log("borrowed ETH after close position", await tETHContract.callStatic.borrowBalanceCurrent(trader.address));
    });
})
