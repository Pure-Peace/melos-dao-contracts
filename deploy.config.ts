/* eslint-disable @typescript-eslint/no-unused-vars */
import { BigNumber, BigNumberish } from 'ethers';
import { ZERO_ADDRESS } from './scripts/constants';


export type DeployConfig = {
  melosToken?: string;
};

const toTokenAmount = (amount: BigNumberish, tokenDecimal: BigNumberish) => {
  return BigNumber.from(amount).mul(BigNumber.from(10).pow(tokenDecimal));
};


const config: { [key: string]: DeployConfig } = {
  mainnet: {
  },
  rinkeby: {

  },
  bsc: {
    melosToken: 'MELOS_TOKEN_ADDRESS'
  }
};


export default config;
