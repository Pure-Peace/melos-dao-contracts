import hre from 'hardhat';
import fs from 'fs';
import path from 'path';

async function main() {
  const basePath = `./deployments/${hre.network.name}`;
  const deployments = fs
    .readdirSync(basePath)
    .filter((f) => f.endsWith('.json'))
    .map((f) => {
      return {
        name: f,
        ...JSON.parse(fs.readFileSync(path.join(basePath, f)).toString()),
      };
    })
    .filter((d) => !!d.address);
  console.log(
    `${hre.network.name}: ${deployments.length} deployments founded.`
  );

  const argumentsForDeployments = deployments.reduce((acc, cur) => {
    console.log(cur.name);
    let arg: any[] = [];
    if (cur.name.endsWith('Proxy.json')) {
      arg = [
        deployments.find(
          (dd) => dd.name === `UpBeacon${cur.name.replace('Proxy', '')}`
        ).address,
        [],
      ];
    } else if (cur.name.startsWith('UpBeacon')) {
      arg = [
        deployments.find(
          (dd) => dd.name === `Impl${cur.name.replace('UpBeacon', '')}`
        ).address,
      ];
    }
    acc[cur.name] = arg;
    return acc;
  }, {});

  for (const d of deployments) {
    if (d.verify) {
      console.log(`${d.name} is already verifyed, skip...`);
      continue;
    }
    console.log(`Verifying contract ${d.name}...`);
    hre
      .run('verify:verify', {
        address: d.address,
        constructorArguments: argumentsForDeployments[d.name],
      })
      .then(() => {
        d.verify = true;
        fs.writeFileSync(path.join(basePath, d.name), JSON.stringify(d));
        console.log(`${d.name} OK`);
      })
      .catch((err) => {
        console.error(`Failed: ${d.name}`, err);
      });
  }
}

main()
  .then(() => {})
  .catch((error) => {
    console.error(error);
  });
