// @ts-ignore
import { ethers } from "hardhat";
import { SECONDS_PER_YEAR } from "@gearbox-protocol/sdk";

const getTimestamp = async (blockN?: number) => {
  const blockNum = blockN || (await ethers.provider.getBlockNumber());
  const currentBlockchainTime = await ethers.provider.getBlock(blockNum);
  return currentBlockchainTime.timestamp;
};

export const oneYearAhead = async () => {
  const currentTimestamp = await getTimestamp();
  const oneYearLater = currentTimestamp + SECONDS_PER_YEAR;
  await ethers.provider.send("evm_mine", [oneYearLater]);
};
