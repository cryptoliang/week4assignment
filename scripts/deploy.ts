import { ethers } from "hardhat";

async function main() {
  const TraderFactory = await ethers.getContractFactory("Trader");
  const trader = await TraderFactory.deploy();
  console.log("Trader contract address: ", trader.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
