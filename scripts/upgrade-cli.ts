/* eslint-disable prefer-const */
/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable @typescript-eslint/no-var-requires */

import {UPBEACON_PREFIX, UPGRADEABLE_CONTRACTS} from './constants';
import {getContractFromEnvOrPrompts, setup, waitContractCall} from './utils';

const prompts = require('prompts');

async function main() {
  const {deploy, deployer} = await setup();
  const {contracts} = await prompts([
    {
      type: 'multiselect',
      name: 'contracts',
      message: 'Select the contract to be upgraded:',
      choices: UPGRADEABLE_CONTRACTS.reduce((pre, cur) => {
        if (typeof cur === 'string') pre.push(cur);
        else pre.push(...cur[Object.keys(cur)[0]]);
        return pre;
      }, [] as any).map((i: string) => {
        return {title: i, value: i};
      }),
    },
  ]);

  console.log('Upgrade the following contracts:', contracts);
  for (const i of contracts) {
    const name = `${UPBEACON_PREFIX}${i}`;
    const contract = await getContractFromEnvOrPrompts<any>(
      {contractNameEnv: name, contractName: 'UpgradeableBeacon'},
      deployer
    );
    const owner = await contract.owner();
    if (owner != deployer.address) {
      throw new Error('You do not have permission to use the upgrade contract');
    }
    console.log(
      `Successfully get upgrade contract at "${
        contract.address
      }" (old implementation: "${await contract.implementation()}")`
    );
    console.log('Deploying a new implementation...');
    const depResult = await deploy(`Impl${i}`, i);
    console.log('Upgrading contract...');
    await waitContractCall(await contract.upgradeTo(depResult.address));
    console.log(`Successfully upgrade contract "${i}"`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
