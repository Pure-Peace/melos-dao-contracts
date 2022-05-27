import {deployAndSetupContracts} from './utils';

deployAndSetupContracts()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('this error', error);
    process.exit(1);
  });
