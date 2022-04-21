import { expect } from './chai-setup';
import * as hre from 'hardhat';
import {
  deployments,
  ethers,
  getNamedAccounts,
  getUnnamedAccounts,
} from 'hardhat';

import { setupUser, setupUsers, setupUsersWithNames } from './utils';
import { getContractForEnvironment } from './utils/getContractForEnvironment';
import { BigNumber } from '@ethersproject/bignumber';

const setup = deployments.createFixture(async () => {
  await deployments.fixture('contracts');
});
