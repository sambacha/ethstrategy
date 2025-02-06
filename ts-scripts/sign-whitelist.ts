import { exec } from 'child_process';
import { promises as fs } from 'node:fs';
import { privateKeyToAccount } from 'viem/accounts'

const signWhitelist = async (privateKey: `0x${string}`) => {
  const data = await fs.readFile('./whitelist.json');
  const whitelist = (await JSON.parse(data)).whitelist;
  const signedWhitelist = new Map<string, string>();

  const account = privateKeyToAccount(privateKey);
 

  for (const address of whitelist) {
    const signature = await account.signMessage({
      // Hex data representation of message.
      message: { raw: address },
    })
    signedWhitelist.set(address, signature);
  }
  fs.writeFile('./signed-whitelist.json', JSON.stringify(Object.fromEntries(signedWhitelist)));
}

signWhitelist(process.env.PRIVATE_KEY);
