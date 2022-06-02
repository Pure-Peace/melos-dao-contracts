/* eslint-disable @typescript-eslint/no-unused-vars */
import {BigNumber, BigNumberish} from 'ethers';
import {ZERO_ADDRESS} from './scripts/constants';

export type DeployConfig = {
  melosToken?: string;
};

const toTokenAmount = (amount: BigNumberish, tokenDecimal: BigNumberish) => {
  return BigNumber.from(amount).mul(BigNumber.from(10).pow(tokenDecimal));
};

const config: {[key: string]: DeployConfig} = {
  mainnet: {},
  rinkeby: {},
  bscTestnet: {
    melosToken: '0xd8b9195bd7585e834de6f221ce5d80f27bde6a5d',
  },
  bsc: {
    melosToken: '0x3CC194Cb21E3B9d86dD516b4d870B82fAfb4C02E',
  },
};

export default config;
