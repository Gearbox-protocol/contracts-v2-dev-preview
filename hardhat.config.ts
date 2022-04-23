import { config as dotEnvConfig } from "dotenv";
import { HardhatUserConfig } from "hardhat/types";

import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-ethers";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "hardhat-abi-exporter";
import "hardhat-contract-sizer";
import "solidity-coverage";
import { LOCAL_NETWORK, MAINNET_NETWORK } from "@gearbox-protocol/sdk";

// gets data from .env file
dotEnvConfig();

const INFURA_API_KEY = process.env.INFURA_API_KEY || "";
const KOVAN_PRIVATE_KEY =
  process.env.KOVAN_PRIVATE_KEY! ||
  "0xc87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3"; // well known private key

const KOVAN2_PRIVATE_KEY =
  process.env.KOVAN2_PRIVATE_KEY! ||
  "0xc87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3"; // well known private key

const BOXCODE_PRIVATE_KEY =
  process.env.BOSXCODE_PRIVATE_KEY! ||
  "0xc87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3"; // well known private key

const BVI_PRIVATE_KEY =
  process.env.BVI_PRIVATE_KEY! ||
  "0xc87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3"; // well known private key

const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  solidity: {
    compilers: [{ version: "0.8.10", settings: {} }],
  },
  networks: {
    hardhat: {
      chainId: LOCAL_NETWORK,
      initialBaseFeePerGas: 0,
      allowUnlimitedContractSize: true,
    },
    localhost: {
      timeout: 0,
    },
    mainnet: {
      url: process.env.ETH_MAINNET_PROVIDER || "",
      accounts: [BOXCODE_PRIVATE_KEY, BVI_PRIVATE_KEY],
      chainId: MAINNET_NETWORK,
      timeout: 0,
      gasMultiplier: 1.15,
      minGasPrice: 1e9,
      allowUnlimitedContractSize: false,
    },

    kovan: {
      url: `https://kovan.infura.io/v3/${INFURA_API_KEY}`,
      accounts: [KOVAN_PRIVATE_KEY, KOVAN2_PRIVATE_KEY],
      gasPrice: 2e9,
      minGasPrice: 1e9,
      timeout: 0,
      allowUnlimitedContractSize: false,
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: ETHERSCAN_API_KEY,
  },
  gasReporter: {
    enabled: false,
    currency: "USD",
    gasPrice: 21,
  },
  typechain: {
    outDir: "types",
    target: "ethers-v5",
  },
  abiExporter: {
    path: "./abi",
    clear: true,
    flat: true,
    spacing: 2,
  },
  contractSizer: {
    alphaSort: false,
    disambiguatePaths: false,
    runOnCompile: true,
  },
};

export default config;
