// Configuration: ~/Library/Application Support/Nodogram/vault.env (owner-only),
// overridable by environment variables. Secrets never live in the repository.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const supportDir = path.join(os.homedir(), "Library", "Application Support", "Nodogram");
export const envFile = process.env.VAULT_ENV_FILE ?? path.join(supportDir, "vault.env");

export function parseEnv(text) {
  const out = {};
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m && !line.trimStart().startsWith("#")) out[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
  return out;
}

export function loadConfig() {
  let file = {};
  try {
    const stat = fs.statSync(envFile);
    if ((stat.mode & 0o077) !== 0) {
      console.warn(`[vault] ${envFile} is readable by others; fixing permissions to 0600`);
      fs.chmodSync(envFile, 0o600);
    }
    file = parseEnv(fs.readFileSync(envFile, "utf8"));
  } catch {
    // No file: rely on the environment.
  }
  const get = (k, d) => process.env[k] ?? file[k] ?? d;
  const config = {
    botToken: get("BOT_TOKEN"),
    ownerId: Number(get("OWNER_ID")),
    ownerUsername: get("OWNER_USERNAME", ""),
    databaseUrl: get("DATABASE_URL", "postgresql://127.0.0.1:5432/nodogram_vault"),
    port: Number(get("VAULT_PORT", "47823")),
    apiToken: get("VAULT_API_TOKEN"),
    mediaDir: get("VAULT_MEDIA_DIR", path.join(supportDir, "vault-media")),
    notifyEdits: get("NOTIFY_EDITS", "true") === "true",
    logChannel: get("LOG_CHANNEL") ? Number(get("LOG_CHANNEL")) : null,
  };
  const missing = ["botToken", "ownerId", "apiToken"].filter((k) => !config[k]);
  if (missing.length) throw new Error(`Missing configuration: ${missing.join(", ")} (see ${envFile})`);
  return config;
}
