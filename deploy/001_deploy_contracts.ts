import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { deployAndSetupContracts } from '../scripts/utils';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  await deployAndSetupContracts()
};
export default func;
func.id = 'deploy_contracts';
func.tags = ['deployContracts'];
