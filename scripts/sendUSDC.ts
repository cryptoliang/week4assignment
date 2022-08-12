import {ethers, network} from "hardhat";
import cronosCRC20ABI from "../abis/cronosCRC20"

const usdcContractAddress = "0xc21223249CA28397B4B6541dfFaEcC539BfF0c59";
const usdcContractOwnerAddress = "0xea01e309146551a67366fe9943E9Ed83Ae564057"

async function main() {
    await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [usdcContractOwnerAddress],
    });

    let usdcContractOwner = await ethers.getImpersonatedSigner(usdcContractOwnerAddress);
    let accounts = await ethers.getSigners();

    const usdcContract = new ethers.Contract(usdcContractAddress, cronosCRC20ABI, usdcContractOwner);

    for (let i = 0; i < 3; i++) {
        let address = accounts[i].address;
        await usdcContract.mint(address, ethers.utils.parseUnits("10000", 6))
        let balance = ethers.utils.formatUnits(await usdcContract.balanceOf(address), 6);
        console.log(`Account #${i} ${address} (${balance} USDC)`)
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
