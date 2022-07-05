import { expect } from './chai-setup';
import * as hre from 'hardhat';
import {
  deployments,
  getNamedAccounts,
} from 'hardhat';

import { getBlockNumber, setupUsersWithNames } from './utils';
import { getContractForEnvironment } from './utils/getContractForEnvironment';
import { MelosGovernorV1, MockMelos, VMelos } from '../typechain';
import { BigNumber } from 'ethers';
import { toTokenAmount } from '../scripts/utils';

const UINT256_MAX = BigNumber.from(2).pow(256).sub(1)

const setup = deployments.createFixture(async () => {
  await deployments.fixture('deployContracts');
  const contracts = {
    MockMelos: await getContractForEnvironment<MockMelos>(hre, 'MockMelos'),
    MelosGovernorV1: await getContractForEnvironment<MelosGovernorV1>(hre, 'MelosGovernorV1'),
    VoteMelos: await getContractForEnvironment<VMelos>(hre, 'vMelos'),
  };
  const users = await setupUsersWithNames((await getNamedAccounts()) as any, contracts);
  return {
    ...contracts,
    users,
  };
});


describe('TEST VOTE MELOS', function () {
  it('test Melos should approve for vMelos', async function () {
    const { users, MockMelos, VoteMelos } = await setup();
    await MockMelos.approve(VoteMelos.address, UINT256_MAX)
    expect(await MockMelos.allowance(users.deployer.address, VoteMelos.address), 'approve failed').to.equal(UINT256_MAX)
  });

  it('should deposit Melos for vMelos success', async function () {
    const { users, MockMelos, VoteMelos } = await setup();
    const depositValue = toTokenAmount(10000)

    await MockMelos.approve(VoteMelos.address, UINT256_MAX)
    await VoteMelos.depositFor(users.deployer.address, depositValue)

    expect(await VoteMelos.balanceOf(users.deployer.address), 'deposit failed').to.equal(depositValue)
  });

  it('should withdraw Melos for vMelos success', async function () {
    const { users, MockMelos, VoteMelos } = await setup();
    const depositValue = toTokenAmount(10000)

    await MockMelos.approve(VoteMelos.address, UINT256_MAX)
    await VoteMelos.depositFor(users.deployer.address, depositValue)
    await VoteMelos.withdrawTo(users.user1.address, depositValue)

    expect(await VoteMelos.balanceOf(users.deployer.address), 'withdraw failed').to.equal(depositValue.sub(depositValue))
  });

  it('deposit testing', async function () {
    const { users, MockMelos, VoteMelos } = await setup();

    await MockMelos.approve(VoteMelos.address, UINT256_MAX)

    await VoteMelos.depositFor(users.deployer.address, toTokenAmount(1000))
    await VoteMelos.depositFor(users.deployer.address, toTokenAmount(100))
    await VoteMelos.depositFor(users.deployer.address, toTokenAmount(100))
  });
});

