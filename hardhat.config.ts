import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: "0.8.9",
  networks: {
    hardhat: {
      forking: {
        url: "https://evm-cronos.crypto.org",
        blockNumber: 4096430
      }
    },
    localhost: {
      url: "http://127.0.0.1:8545/",
      chainId: 31337,
      timeout: 100_000
    },
    cronos: {
      url: "https://evm-cronos.crypto.org",
      chainId: 25,
    }
  },
  mocha: {
    timeout: 100000000
  },
  defaultNetwork: "localhost"
};

export default config;
