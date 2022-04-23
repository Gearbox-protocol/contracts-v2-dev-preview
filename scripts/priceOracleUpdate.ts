// @ts-ignore
import { ethers, network } from "hardhat";
import {
  ACL__factory,
  AddressProvider__factory, PriceOracle__factory, tokenDataByNetwork
} from "@gearbox-protocol/sdk";
// @ts-ignore
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/root-with-address";
import * as dotenv from "dotenv";

import { Logger } from "tslog";
import { waitForTransaction } from "../utils/transaction";


// This example shows how to add new token to PriceOracle
async function priceOracleUpdate() {
  dotenv.config({ path: ".env.kovan" });
  const log: Logger = new Logger();

  // Gets accounts
  const accounts = (await ethers.getSigners()) as Array<SignerWithAddress>;
  const deployer = accounts[0];

  // Checks that we're on fork net, not to make real changes
  const chainId =  await deployer.getChainId();
  if (chainId !== 1337) throw new Error("Only for Kovan forks only");

  // Shows deployer addr for debug purposes
  log.debug(`DEPLOYER ${deployer.address}`);

  // Gets address of Address provider for contracts discovery
  const addressProvider = AddressProvider__factory.connect(
    process.env.REACT_APP_ADDRESS_PROVIDER || "",
    deployer
  );

  // Gets address of CONFIGURATOR role
  const acl = ACL__factory.connect(await addressProvider.getACL(), deployer);
  const configurator = await acl.owner();

  // Prints configurator address
  log.debug(`Configurator: ${configurator}`);

  // Impersonates CONFIGURATOR and make a root account which can manage system
  log.info("Impersonate mulsisig account");
  await network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [configurator],
  });

  const root = (await ethers.provider.getSigner(
    configurator
  )) as unknown as SignerWithAddress;



  // Gets priceOracl contact
  const priceOracle = await PriceOracle__factory.connect(
    await addressProvider.getPriceOracle(),
    deployer
  );

  // To call addPriceFeed you should have real ERC20 and priceFeed
  // In this artifical example we use priceFeed for USDC token and set it to DAI
  // In your code, please deploy priceFeed code here and provide valid ERC20 token as well
  const usdPriceFeed = await priceOracle.priceFeeds(
    tokenDataByNetwork.Kovan.USDC
  );

  log.debug(`USDC priceFeed: ${usdPriceFeed}`);

  // Adds token to priceFeed
  await waitForTransaction(
    priceOracle
      .connect(root)
      .addPriceFeed(tokenDataByNetwork.Kovan.DAI, usdPriceFeed)
  );
}

priceOracleUpdate()
  .then(() => console.log("Ok"))
  .catch((e) => console.log(e));
