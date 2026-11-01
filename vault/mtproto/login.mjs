// ONE-TIME LOGIN — YOU run this yourself. It never shares your code or password
// with anyone; everything you type stays on your machine.
//
//   node login.mjs
//
// It asks for your phone, the Telegram login code, and (if you have one) your
// 2FA password, then prints a SESSION STRING. Put that string in .env as
// MTPROTO_SESSION. The watcher then stays logged in on its own — no Nodogram,
// no Mac needed once it runs on a server.
//
// First get API_ID and API_HASH from https://my.telegram.org (API development
// tools) and put them in .env as API_ID and API_HASH.
//
// SECURITY: the session string gives FULL access to your Telegram account.
// Keep it secret, store it only in .env (chmod 600), never commit or share it.
// If it ever leaks, revoke it in Telegram → Settings → Devices.

import { TelegramClient } from "telegram";
import { StringSession } from "telegram/sessions/index.js";
import readline from "node:readline/promises";
import { stdin as input, stdout as output } from "node:process";
import { loadEnv } from "./env.mjs";

const env = loadEnv();
const apiId = Number(env.API_ID);
const apiHash = env.API_HASH;
if (!apiId || !apiHash) {
  console.error("Missing API_ID / API_HASH. Get them at https://my.telegram.org and put them in .env");
  process.exit(1);
}

const rl = readline.createInterface({ input, output });
const ask = (q) => rl.question(q);

const client = new TelegramClient(new StringSession(""), apiId, apiHash, { connectionRetries: 5 });

console.log("Logging in… your code and password stay on this machine only.\n");
await client.start({
  phoneNumber: async () => (await ask("Phone (e.g. +99890…): ")).trim(),
  password: async () => (await ask("2FA password (leave blank if you have none): ")).trim(),
  phoneCode: async () => (await ask("Login code Telegram just sent you: ")).trim(),
  onError: (err) => console.error("Login error:", err?.message || err),
});

const session = client.session.save();
console.log("\n=================  SESSION STRING (keep secret)  =================\n");
console.log(session);
console.log("\n==================================================================");
console.log("Add this line to the .env file next to the watcher:\n");
console.log("MTPROTO_SESSION=" + session);
console.log("\nThen run the watcher:  node watcher.mjs   (or set up the service — see README.md)");
await client.disconnect();
await rl.close();
process.exit(0);
