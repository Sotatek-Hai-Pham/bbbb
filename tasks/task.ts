import { task } from "hardhat/config";
import {
  FixedToken__factory,
} from "../typechain";

task("create-fixed-token").setAction(async (_, hre) => {
  const { deployments, ethers } = hre;
  const [deployer] = await ethers.getSigners();

  const stakeToken = await FixedToken__factory.connect(
    (
      await deployments.get("FixedToken")
    ).address,
    deployer,
  );

  console.log("\x1b[36m%s\x1b[0m", "autoCompounderAddress", stakeToken.address);
});
