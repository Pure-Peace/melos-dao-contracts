export type ContractList = (string | {[key: string]: string[]})[];

export const GAS_LIMIT = 5500000;

export const UPGRADEABLE_CONTRACTS: ContractList = [
  'vMelos',
  'MelosGovernorV1',
  'vMelosStaking',
];

export const IMPL_PREFIX = 'Impl';
export const UPBEACON_PREFIX = 'UpBeacon';

export const PROXY_CONTRACTS: ContractList = [
  'vMelos',
  'MelosGovernorV1',
  'vMelosStaking',
];

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
