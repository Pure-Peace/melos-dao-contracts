import { ethers, Signer } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

function genGetContractWith(hre: HardhatRuntimeEnvironment) {
  async function getContractWithAt<T extends ethers.Contract>(hre: HardhatRuntimeEnvironment, contractName: string, address: string, signer?: string | Signer | undefined): Promise<T> {

    const realSigner = (typeof signer === 'string' ? (await hre.ethers.getSigner(signer)) : signer);


    try {
      const contract = await hre.deployments.get(contractName);
      return hre.ethers.getContractAt(contract.abi, address, realSigner) as Promise<T>;
    } catch (err) {
      return hre.ethers.getContractAt(contractName, address, realSigner) as Promise<T>;
    }

  }
  async function getContractWith<T extends ethers.Contract>(hre: HardhatRuntimeEnvironment, contractName: string, signer?: string | Signer | undefined): Promise<T> {

    const realSigner = (typeof signer === 'string' ? (await hre.ethers.getSigner(signer)) : signer);

    const contract = await hre.deployments.get(contractName);
    return hre.ethers.getContractAt(contract.abi, contract.address, realSigner) as Promise<T>;

  }

  const getContract = <T extends ethers.Contract>(contractName: string, signer?: string | Signer | undefined): Promise<T> => getContractWith<T>(hre, contractName, signer);
  const getContractAt = <T extends ethers.Contract>(contractName: string, address: string, signer?: string | Signer | undefined): Promise<T> => getContractWithAt<T>(hre, contractName, address, signer);
  return { getContract, getContractAt };
}

export {
  genGetContractWith,
}
