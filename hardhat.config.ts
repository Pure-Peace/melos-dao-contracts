import 'dotenv/config';
import { HardhatUserConfig } from 'hardhat/types';
import 'hardhat-deploy';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-etherscan';
import 'hardhat-contract-sizer';
import 'hardhat-gas-reporter';
import '@typechain/hardhat';
import 'solidity-coverage';
import 'hardhat-docgen';
import 'hardhat-abi-exporter';
//import "@atixlabs/hardhat-time-n-mine";
import { node_url, accounts } from './utils/network';

// While waiting for hardhat PR: https://github.com/nomiclabs/hardhat/pull/1542
if (process.env.HARDHAT_FORK) {
  process.env['HARDHAT_DEPLOY_FORK'] = process.env.HARDHAT_FORK;
}

const config = {
  solidity: {
    version: '0.8.13',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  namedAccounts: {
    deployer: 0,
    user1: 1,
    user2: 2
  },
  networks: {
    hardhat: {
      initialBaseFeePerGas: 10, // to fix : https://github.com/sc-forks/solidity-coverage/issues/652, see https://github.com/sc-forks/solidity-coverage/issues/652#issuecomment-896330136
      // process.env.HARDHAT_FORK will specify the network that the fork is made from.
      // this line ensure the use of the corresponding accounts
      accounts: accounts(process.env.HARDHAT_FORK),
      forking: process.env.HARDHAT_FORK
        ? {
          // TODO once PR merged : network: process.env.HARDHAT_FORK,
          url: node_url(process.env.HARDHAT_FORK),
          blockNumber: process.env.HARDHAT_FORK_NUMBER
            ? parseInt(process.env.HARDHAT_FORK_NUMBER)
            : undefined,
        }
        : undefined,
    },
    localhost: {
      url: node_url('localhost'),
      accounts: accounts(),
    },
    staging: {
      url: node_url('rinkeby'),
      accounts: accounts('rinkeby'),
    },
    production: {
      url: node_url('mainnet'),
      accounts: accounts('mainnet'),
    },
    mainnet: {
      url: node_url('mainnet'),
      accounts: accounts('mainnet'),
    },
    rinkeby: {
      url: node_url('rinkeby'),
      accounts: accounts('rinkeby'),
    },
    kovan: {
      url: node_url('kovan'),
      accounts: accounts('kovan'),
    },
    goerli: {
      url: node_url('goerli'),
      accounts: accounts('goerli'),
    },
    ropsten: {
      url: node_url('ropsten'),
      accounts: accounts('ropsten'),
    },
    bscTestnet: {
      url: node_url('bscTestnet'),
      accounts: accounts('bscTestnet'),
    },
    bsc: {
      url: node_url('bsc'),
      accounts: accounts('bsc'),
    },
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEYS,
      ropsten: process.env.ETHERSCAN_API_KEYS,
      rinkeby: process.env.ETHERSCAN_API_KEYS,
      goerli: process.env.ETHERSCAN_API_KEYS,
      kovan: process.env.ETHERSCAN_API_KEYS,
      bscTestnet: process.env.ETHERSCAN_API_KEYS_BSC,
      bsc: process.env.ETHERSCAN_API_KEYS_BSC,
    },
  },
  paths: {
    sources: 'src',
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 100,
    enabled: process.env.REPORT_GAS ? true : false,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    maxMethodDiff: 10,
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: true,
  },
  mocha: {
    timeout: 0,
  },
  docgen: {
    path: './docs',
    clear: true,
    runOnCompile: true,
  },
  abiExporter: {
    path: './abibuild',
    clear: true,
    flat: true,
    spacing: 2,
    pretty: true,
  },
};

export default config;
