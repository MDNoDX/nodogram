// A small read-only API for the Nodogram app, on 127.0.0.1 only, behind a
// bearer token from vault.env. Nothing here is reachable from the network.

import http from "node:http";
import fs from "node:fs";
import crypto from "node:crypto";

export function startAPI({ config, db, log = console }) {
  const token = Buffer.from(config.apiToken);
  const authorized = (req) => {
    const given = Buffer.from((req.headers.authorization ?? "").replace(/^Bearer\s+/i, ""));
    return given.length === token.length && crypto.timingSafeEqual(given, token);
  };

  const server = http.createServer(async (req, res) => {
    const send = (status, body) => {
      res.writeHead(status, { "content-type": "application/json", "cache-control": "no-store" });
      res.end(JSON.stringify(body));
    };
    try {
      if (!authorized(req)) return send(401, { error: "unauthorized" });
      const url = new URL(req.url, "http://127.0.0.1");
      const since = url.searchParams.get("since");
      const chatId = url.searchParams.get("chat");
      const limit = Math.min(Number(url.searchParams.get("limit") ?? 200), 1000);
      if (url.pathname === "/v1/status") {
        return send(200, { ok: true, stats: await db.stats(), connections: (await db.activeConnections()).length });
      }
      if (url.pathname === "/v1/deleted") {
        return send(200, { messages: (await db.deleted({ since, chatId, limit })).map(shape) });
      }
      if (url.pathname === "/v1/edited") {
        return send(200, { messages: (await db.edited({ since, chatId, limit })).map(shape) });
      }
      const versions = url.pathname.match(/^\/v1\/versions\/(-?\d+)\/(\d+)$/);
      if (versions) {
        const rows = await db.versions(versions[1], versions[2]);
        return send(200, { versions: rows.map((r) => ({ version: r.version, text: r.text, at: r.at })) });
      }
      const media = url.pathname.match(/^\/v1\/media\/(-?\d+)\/(\d+)$/);
      if (media) {
        const r = await db.pool.query("SELECT local_path FROM messages WHERE chat_id = $1 AND message_id = $2", [media[1], media[2]]);
        const file = r.rows[0]?.local_path;
        if (!file || !fs.existsSync(file)) return send(404, { error: "no media" });
        res.writeHead(200, { "content-type": "application/octet-stream" });
        return fs.createReadStream(file).pipe(res);
      }
      send(404, { error: "not found" });
    } catch (error) {
      log.error?.("[vault] api error:", error);
      send(500, { error: "internal" });
    }
  });
  server.listen(config.port, "127.0.0.1", () => log.info?.(`[vault] api on 127.0.0.1:${config.port}`));
  return server;
}

/** API shape: plain numbers and ISO dates. */
export function shape(row) {
  return {
    chatId: Number(row.chat_id),
    messageId: Number(row.message_id),
    chatTitle: row.chat_title,
    chatUsername: row.chat_username,
    senderId: row.sender_id === null ? null : Number(row.sender_id),
    senderName: row.sender_name,
    isOutgoing: row.is_outgoing,
    sentAt: row.sent_at,
    text: row.text,
    mediaKind: row.media_kind,
    localPath: row.local_path,
    editedAt: row.edited_at,
    deletedAt: row.deleted_at,
  };
}
