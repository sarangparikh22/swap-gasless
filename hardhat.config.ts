import { task } from "hardhat/config";
import "@nomiclabs/hardhat-waffle";


const accounts = "test test test test test test test test test test test junk";

task("accounts", "Prints the list of accounts", async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

export default {
  solidity: "0.6.12",
  networks: {
    // goerli: {
    //   url: 'https://goerli.infura.io/v3/ae01c2f20b6046b1b351e20a79eba386',
    //   accounts: [""],
    //   chainId: 5,
    // }
  }
};
