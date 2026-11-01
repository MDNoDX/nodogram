// Loads configuration for the standalone watcher. Portable: reads a .env file
// next to this script first (for a VPS), then process.env, then the Mac's
// vault.env as a convenience when run on the same Mac. No secrets are logged.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

function parse(file, into) {
  try {
    for (const line of fs.readFileSync(file, "utf8").split("\n")) {
      if (!line || line.startsWith("#")) continue;
      const i = line.indexOf("=");
      if (i > 0) {
        const k = line.slice(0, i).trim();
        if (into[k] === undefined) into[k] = line.slice(i + 1).trim();
      }
    }
  } catch { /* file may not exist */ }
}

export function loadEnv() {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const env = {};
  // 1) a local .env beside the watcher (recommended on a VPS)
  parse(path.join(here, ".env"), env);
  // 2) real environment variables (systemd / docker / shell export)
  for (const k of ["API_ID", "API_HASH", "MTPROTO_SESSION", "BOT_TOKEN", "LOG_CHANNEL", "OWNER_ID", "REPORT_MESSAGES"]) {
    if (env[k] === undefined && process.env[k] !== undefined) env[k] = process.env[k];
  }
  // 3) the Mac's shared vault.env, for convenience when run on the same Mac
  parse(path.join(os.homedir(), "Library/Application Support/Nodogram/vault.env"), env);
  return env;
}
