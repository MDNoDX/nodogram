// A small Bot API client: long polling, retries with Telegram's retry_after,
// file downloads, and media re-sending.

import fs from "node:fs";
import path from "node:path";

export class BotAPI {
  constructor(token) {
    this.base = `https://api.telegram.org/bot${token}`;
    this.fileBase = `https://api.telegram.org/file/bot${token}`;
  }

  async call(method, params = {}, { timeoutMs = 70_000 } = {}) {
    for (let attempt = 0; ; attempt++) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      try {
        const res = await fetch(`${this.base}/${method}`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(params),
          signal: controller.signal,
        });
        const body = await res.json();
        if (body.ok) return body.result;
        const retry = body.parameters?.retry_after;
        if (retry && attempt < 5) { await sleep(retry * 1000); continue; }
        throw new BotError(method, body.error_code, body.description);
      } catch (error) {
        if (error instanceof BotError) throw error;
        if (attempt >= 5) throw error;
        await sleep(Math.min(30_000, 1000 * 2 ** attempt));   // network: back off
      } finally {
        clearTimeout(timer);
      }
    }
  }

  /** Sends a file from disk (multipart), for media whose file_id no longer works. */
  async upload(method, field, filePath, params = {}) {
    const form = new FormData();
    for (const [k, v] of Object.entries(params)) {
      if (v !== undefined && v !== null) form.append(k, typeof v === "object" ? JSON.stringify(v) : String(v));
    }
    const data = await fs.promises.readFile(filePath);
    form.append(field, new Blob([data]), path.basename(filePath));
    const res = await fetch(`${this.base}/${method}`, { method: "POST", body: form });
    const body = await res.json();
    if (!body.ok) throw new BotError(method, body.error_code, body.description);
    return body.result;
  }

  /** Downloads a file the bot can see (Bot API limit: 20 MB). */
  async download(fileId, destination) {
    const file = await this.call("getFile", { file_id: fileId });
    if (!file.file_path) return null;
    const res = await fetch(`${this.fileBase}/${file.file_path}`);
    if (!res.ok) return null;
    const ext = path.extname(file.file_path) || "";
    const target = destination + ext;
    await fs.promises.mkdir(path.dirname(target), { recursive: true });
    await fs.promises.writeFile(target, Buffer.from(await res.arrayBuffer()), { mode: 0o600 });
    return target;
  }
}

export class BotError extends Error {
  constructor(method, code, description) {
    super(`${method}: ${code} ${description}`);
    this.code = code;
    this.description = description;
  }
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
