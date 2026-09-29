import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";
import { subtask } from "hardhat/config";
import { TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD } from "hardhat/builtin-tasks/task-names";

const LOCAL_SOLC_VERSION = "0.8.28";

subtask(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD).setAction(
  async (args, _hre, runSuper) => {
    if (args.solcVersion !== LOCAL_SOLC_VERSION) return runSuper();

    const solc = require("solc");
    return {
      compilerPath: require.resolve("solc/soljson.js"),
      isSolcJs: true,
      version: LOCAL_SOLC_VERSION,
      longVersion: solc.version(),
    };
  },
);

export default {
  solidity: {
    version: LOCAL_SOLC_VERSION,
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
    hardhat: { chainId: 31337 },
  },
};
