import {Signer, Contract} from 'ethers';
import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {genGetContractWith} from './genHelpers';
type THardHatLookupHelper<T> = (
  hre: HardhatRuntimeEnvironment,
  contractSlug: string,
  signer?: string | Signer | undefined
) => Promise<T>;
function generateEnvNameContractDefHelper(
  networkToContract: {[networkName: string]: string},
  {abiName, lookupName}: {abiName?: string; lookupName?: string} = {}
): THardHatLookupHelper<any> {
  return async (
    hre: HardhatRuntimeEnvironment,
    contractSlug: string,
    signer?: string | Signer | undefined
  ) => {
    const {getContract, getContractAt} = genGetContractWith(hre);
    const addressOrAbi =
      Object.prototype.hasOwnProperty.call(
        networkToContract,
        hre.network.name
      ) && networkToContract[hre.network.name]
        ? networkToContract[hre.network.name]
        : null;
    const contractAddressOverride =
      addressOrAbi && addressOrAbi.substring(0, 2) === '0x'
        ? addressOrAbi
        : null;
    const contractAbiName = contractAddressOverride
      ? abiName || contractSlug
      : contractAddressOverride || abiName || contractSlug;
    if (contractAddressOverride) {
      return getContractAt(
        lookupName || contractAbiName,
        contractAddressOverride,
        signer
      );
    } else {
      if (abiName && lookupName && lookupName !== abiName) {
        const realContract = await getContract(lookupName);
        return getContractAt(contractAbiName, realContract.address, signer);
      } else {
        return getContract(contractAbiName, signer);
      }
    }
  };
}
const DEF_GET_CONTRACT_FOR_ENVIRONMENT = {
  MockMelos: generateEnvNameContractDefHelper(
    {},
    {lookupName: 'MockMelos', abiName: 'MockMelos'}
  ),
  MelosGovernorV1: generateEnvNameContractDefHelper(
    {},
    {lookupName: 'MelosGovernorV1Proxy', abiName: 'MelosGovernorV1'}
  ),
  vMelos: generateEnvNameContractDefHelper(
    {},
    {lookupName: 'vMelosProxy', abiName: 'vMelos'}
  ),
  vMelosStaking: generateEnvNameContractDefHelper(
    {},
    {
      lookupName: 'vMelosStakingProxy',
      abiName: 'vMelosStaking',
    }
  ),
};
type TContractSlug = keyof typeof DEF_GET_CONTRACT_FOR_ENVIRONMENT;

async function getContractForEnvironment<T>(
  hre: HardhatRuntimeEnvironment,
  contractSlug: TContractSlug,
  signer?: string | Signer | undefined
): Promise<T> {
  return DEF_GET_CONTRACT_FOR_ENVIRONMENT[contractSlug](
    hre,
    contractSlug,
    signer
  );
}
export type {TContractSlug};
export {getContractForEnvironment};
