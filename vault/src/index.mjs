// Nodogram Vault entry point.

import { loadConfig } from "./config.mjs";
import { VaultDB } from "./db.mjs";
import { BotAPI } from "./telegram.mjs";
import { Vault } from "./service.mjs";
import { startAPI } from "./api.mjs";

const log = {
  info: (...a) => console.log(new Date().toISOString(), ...a),
  warn: (...a) => console.warn(new Date().toISOString(), ...a),
  error: (...a) => console.error(new Date().toISOString(), ...a),
};

const config = loadConfig();
const db = new VaultDB(config.databaseUrl);
await db.migrate();
const bot = new BotAPI(config.botToken);
const me = await bot.call("getMe");
log.info(`[vault] running as @${me.username}; Secretary Mode ${me.can_connect_to_business ? "on" : "OFF — turn it on in @BotFather (Bot Settings → Secretary Mode)"}`);

const vault = new Vault({ config, db, bot, log });
const server = startAPI({ config, db, log });

const shutdown = async () => {
  vault.stop();
  server.close();
  await db.close().catch(() => {});
  process.exit(0);
};
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);

await vault.run();
