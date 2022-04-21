import { Contract, Signer } from 'ethers';
import { ethers } from 'hardhat';
import hardhatConfig from '../../hardhat.config';

export async function setupUsers<T extends { [contractName: string]: Contract }>(
  addresses: string[],
  contracts: T
): Promise<({ address: string } & T)[]> {
  const users: ({ address: string } & T)[] = [];
  for (const address of addresses) {
    users.push(await setupUser(address, contracts));
  }
  return users;
}

export async function setupUser<T extends { [contractName: string]: Contract }>(
  address: string | { address: string } | Signer,
  contracts: T
): Promise<{ address: string } & T> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const signer = (address instanceof ethers.Signer) ? (address) : (await ethers.getSigner(typeof address === 'string' ? address : address.address));
  const realAddress = typeof address === 'string' ? address : (await signer.getAddress());
  const user: any = { address: realAddress };


  for (const key of Object.keys(contracts)) {
    user[key] = contracts[key].connect(signer);
  }
  return user as { address: string } & T;
}



export async function setupUsersWithNames<T extends { [contractName: string]: Contract }, K extends { [k in keyof typeof hardhatConfig.namedAccounts]: string }>(
  usersWithNames: K,
  contracts: T,

): Promise<({ [k in keyof typeof hardhatConfig.namedAccounts]: { address: string } & T })> {
  const output: any = {};
  for (const k of Object.keys(usersWithNames)) {
    output[k] = await setupUser(usersWithNames[k as keyof typeof hardhatConfig.namedAccounts], { ...contracts });
  }
  return output;
}
