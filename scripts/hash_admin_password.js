#!/usr/bin/env node
/**
 * Prints the ADMIN_MASTER_PASS_HASH value for Website/api/admin-auth.js.
 *
 *     node scripts/hash_admin_password.js
 *
 * Prompts for the password (not echoed, never passed on the command line where
 * shell history would keep it) and prints `scrypt$<salt>$<hash>`. Put that in
 * the Vercel project's environment variables — never in a file in this repo.
 */
const crypto = require('crypto');
const readline = require('readline');

const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
rl._writeToOutput = (s) => { if (s.includes('Password')) rl.output.write(s); };

rl.question('Password: ', (password) => {
  rl.close();
  process.stdout.write('\n');
  if (password.trim().length < 12) {
    console.error('Use at least 12 characters.');
    process.exit(1);
  }
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(password.trim(), salt, 64);
  console.log(`scrypt$${salt.toString('hex')}$${hash.toString('hex')}`);
});
