// PostgreSQL storage. Every message from connected private chats is kept as it
// arrives, so a later deletion or edit can be shown with what was there.

import pg from "pg";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS vault_state (
  key   text PRIMARY KEY,
  value text NOT NULL
);
CREATE TABLE IF NOT EXISTS business_connections (
  id            text PRIMARY KEY,
  user_id       bigint NOT NULL,
  user_chat_id  bigint NOT NULL,
  is_enabled    boolean NOT NULL,
  rights        jsonb,
  connected_at  timestamptz NOT NULL,
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS messages (
  chat_id        bigint      NOT NULL,
  message_id     bigint      NOT NULL,
  connection_id  text        NOT NULL,
  chat_title     text        NOT NULL DEFAULT '',
  chat_username  text        NOT NULL DEFAULT '',
  sender_id      bigint,
  sender_name    text        NOT NULL DEFAULT '',
  is_outgoing    boolean     NOT NULL,
  sent_at        timestamptz NOT NULL,
  text           text        NOT NULL DEFAULT '',
  media_kind     text,
  file_id        text,
  file_unique_id text,
  local_path     text,
  is_protected   boolean     NOT NULL DEFAULT false,
  reply_to       bigint,
  edited_at      timestamptz,
  deleted_at     timestamptz,
  notified_at    timestamptz,
  raw            jsonb       NOT NULL,
  stored_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (chat_id, message_id)
);
CREATE INDEX IF NOT EXISTS messages_deleted ON messages (deleted_at DESC) WHERE deleted_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS messages_chat ON messages (chat_id, sent_at DESC);
CREATE TABLE IF NOT EXISTS memory (
  id         serial PRIMARY KEY,
  category   text NOT NULL DEFAULT 'note',
  content    text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS watchlist (
  person_id   bigint PRIMARY KEY,
  label       text NOT NULL DEFAULT '',
  username    text NOT NULL DEFAULT '',
  note        text NOT NULL DEFAULT '',
  added_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS message_versions (
  chat_id    bigint      NOT NULL,
  message_id bigint      NOT NULL,
  version    integer     NOT NULL,
  text       text        NOT NULL,
  at         timestamptz NOT NULL,
  PRIMARY KEY (chat_id, message_id, version)
);
`;

export class VaultDB {
  constructor(url) {
    this.pool = new pg.Pool({ connectionString: url, max: 4 });
  }

  async migrate() {
    await this.pool.query(SCHEMA);
  }

  async close() {
    await this.pool.end();
  }

  async getState(key, fallback = null) {
    const r = await this.pool.query("SELECT value FROM vault_state WHERE key = $1", [key]);
    return r.rows[0]?.value ?? fallback;
  }

  async setState(key, value) {
    await this.pool.query(
      "INSERT INTO vault_state (key, value) VALUES ($1, $2) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value",
      [key, String(value)],
    );
  }

  async saveConnection(c) {
    await this.pool.query(
      `INSERT INTO business_connections (id, user_id, user_chat_id, is_enabled, rights, connected_at)
       VALUES ($1,$2,$3,$4,$5,to_timestamp($6))
       ON CONFLICT (id) DO UPDATE SET is_enabled = EXCLUDED.is_enabled, rights = EXCLUDED.rights, updated_at = now()`,
      [c.id, c.user.id, c.user_chat_id, c.is_enabled, c.rights ?? null, c.date],
    );
  }

  async connectionOwner(id) {
    const r = await this.pool.query("SELECT user_id FROM business_connections WHERE id = $1", [id]);
    return r.rows[0] ? Number(r.rows[0].user_id) : null;
  }

  async activeConnections() {
    const r = await this.pool.query("SELECT * FROM business_connections WHERE is_enabled ORDER BY updated_at DESC");
    return r.rows;
  }

  /** Stores a message the first time it is seen; a repeat delivery is ignored. */
  async saveMessage(m) {
    await this.pool.query(
      `INSERT INTO messages (chat_id, message_id, connection_id, chat_title, chat_username, sender_id, sender_name,
         is_outgoing, sent_at, text, media_kind, file_id, file_unique_id, is_protected, reply_to, raw)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,to_timestamp($9),$10,$11,$12,$13,$14,$15,$16)
       ON CONFLICT (chat_id, message_id) DO NOTHING`,
      [m.chatId, m.messageId, m.connectionId, m.chatTitle, m.chatUsername, m.senderId, m.senderName,
       m.isOutgoing, m.date, m.text, m.mediaKind, m.fileId, m.fileUniqueId, m.isProtected, m.replyTo, m.raw],
    );
    await this.pool.query(
      `INSERT INTO message_versions (chat_id, message_id, version, text, at)
       VALUES ($1,$2,0,$3,to_timestamp($4)) ON CONFLICT DO NOTHING`,
      [m.chatId, m.messageId, m.text, m.date],
    );
  }

  async setLocalPath(chatId, messageId, localPath) {
    await this.pool.query("UPDATE messages SET local_path = $3 WHERE chat_id = $1 AND message_id = $2",
      [chatId, messageId, localPath]);
  }

  /** Records an edit. Returns the previous text, or null when unknown or unchanged. */
  async saveEdit(chatId, messageId, text, editDate, raw) {
    const r = await this.pool.query("SELECT text FROM messages WHERE chat_id = $1 AND message_id = $2", [chatId, messageId]);
    if (!r.rows[0]) return { known: false, previous: null };
    const previous = r.rows[0].text;
    if (previous === text) return { known: true, previous: null };
    const v = await this.pool.query(
      "SELECT COALESCE(MAX(version), 0) + 1 AS next FROM message_versions WHERE chat_id = $1 AND message_id = $2",
      [chatId, messageId]);
    await this.pool.query(
      "INSERT INTO message_versions (chat_id, message_id, version, text, at) VALUES ($1,$2,$3,$4,to_timestamp($5))",
      [chatId, messageId, v.rows[0].next, text, editDate]);
    await this.pool.query(
      "UPDATE messages SET text = $3, edited_at = to_timestamp($4), raw = $5 WHERE chat_id = $1 AND message_id = $2",
      [chatId, messageId, text, editDate, raw]);
    return { known: true, previous };
  }

  /** Marks messages deleted and returns the ones newly marked, with content. */
  async markDeleted(chatId, messageIds) {
    const r = await this.pool.query(
      `UPDATE messages SET deleted_at = now()
       WHERE chat_id = $1 AND message_id = ANY($2::bigint[]) AND deleted_at IS NULL
       RETURNING *`,
      [chatId, messageIds]);
    return r.rows;
  }

  async markNotified(chatId, messageId) {
    await this.pool.query("UPDATE messages SET notified_at = now() WHERE chat_id = $1 AND message_id = $2", [chatId, messageId]);
  }

  async deleted({ since = null, chatId = null, limit = 200 } = {}) {
    const r = await this.pool.query(
      `SELECT * FROM messages
       WHERE deleted_at IS NOT NULL AND NOT is_outgoing
         AND ($1::timestamptz IS NULL OR deleted_at > $1) AND ($2::bigint IS NULL OR chat_id = $2)
       ORDER BY deleted_at DESC LIMIT $3`,
      [since, chatId, limit]);
    return r.rows;
  }

  async edited({ since = null, chatId = null, limit = 200 } = {}) {
    const r = await this.pool.query(
      `SELECT * FROM messages
       WHERE edited_at IS NOT NULL AND ($1::timestamptz IS NULL OR edited_at > $1) AND ($2::bigint IS NULL OR chat_id = $2)
       ORDER BY edited_at DESC LIMIT $3`,
      [since, chatId, limit]);
    return r.rows;
  }

  async versions(chatId, messageId) {
    const r = await this.pool.query(
      "SELECT version, text, at FROM message_versions WHERE chat_id = $1 AND message_id = $2 ORDER BY version",
      [chatId, messageId]);
    return r.rows;
  }

  async search(query, limit = 20) {
    const r = await this.pool.query(
      `SELECT * FROM messages WHERE text ILIKE '%' || $1 || '%' ORDER BY sent_at DESC LIMIT $2`, [query, limit]);
    return r.rows;
  }

  /// Distinct chats the vault has seen (incoming side), most recent first.
  async chats(limit = 40) {
    const r = await this.pool.query(
      `SELECT chat_id, MAX(chat_title) AS chat_title, MAX(chat_username) AS chat_username,
              COUNT(*)::int AS messages, MAX(sent_at) AS last_at
       FROM messages WHERE chat_id > 0
       GROUP BY chat_id ORDER BY MAX(sent_at) DESC LIMIT $1`, [limit]);
    return r.rows;
  }

  /// The chat whose title best matches a name, with its id.
  async findChat(name) {
    const r = await this.pool.query(
      `SELECT chat_id, MAX(chat_title) AS chat_title FROM messages
       WHERE chat_id > 0 AND (chat_title ILIKE '%' || $1 || '%' OR chat_username ILIKE '%' || $1 || '%')
       GROUP BY chat_id ORDER BY MAX(sent_at) DESC LIMIT 1`, [name]);
    return r.rows[0] ?? null;
  }

  /// A chat's messages, oldest first, for analysis.
  async chatMessages(chatId, limit = 300) {
    const r = await this.pool.query(
      `SELECT sender_name, is_outgoing, sent_at, text, media_kind, deleted_at, edited_at
       FROM messages WHERE chat_id = $1 ORDER BY sent_at DESC LIMIT $2`, [chatId, limit]);
    return r.rows.reverse();
  }

  /// The latest messages across all private chats, for a general question.
  async recentAcross(limit = 120) {
    const r = await this.pool.query(
      `SELECT chat_title, sender_name, is_outgoing, sent_at, text, media_kind
       FROM messages WHERE chat_id > 0 AND text <> '' ORDER BY sent_at DESC LIMIT $1`, [limit]);
    return r.rows.reverse();
  }

  // ── Watchlist (your own vantage: a person's interactions with YOU) ──────
  async watch(personId, { label = "", username = "", note = "" } = {}) {
    await this.pool.query(
      `INSERT INTO watchlist (person_id, label, username, note) VALUES ($1,$2,$3,$4)
       ON CONFLICT (person_id) DO UPDATE SET label=EXCLUDED.label, username=EXCLUDED.username, note=EXCLUDED.note`,
      [personId, label, username, note]);
  }
  async unwatch(personId) {
    const r = await this.pool.query(`DELETE FROM watchlist WHERE person_id=$1`, [personId]);
    return r.rowCount > 0;
  }
  async watched() {
    const r = await this.pool.query(`SELECT person_id, label, username, note, added_at FROM watchlist ORDER BY added_at DESC`);
    return r.rows;
  }
  async isWatched(personId) {
    if (personId == null) return null;
    const r = await this.pool.query(`SELECT label FROM watchlist WHERE person_id=$1`, [personId]);
    return r.rows[0]?.label ?? null;
  }

  /// The most recently active private chat where the OTHER person wrote last
  /// (i.e. someone is likely waiting for the user's reply). Returns the chat
  /// and its recent messages for suggesting a reply.
  async latestConversation() {
    const r = await this.pool.query(
      `SELECT chat_id, MAX(chat_title) AS chat_title, MAX(sent_at) AS last_at,
              bool_or(NOT is_outgoing AND sent_at = (SELECT MAX(sent_at) FROM messages m2 WHERE m2.chat_id = m.chat_id)) AS waiting
       FROM messages m
       WHERE chat_id > 0 AND text <> ''
       GROUP BY chat_id
       ORDER BY MAX(sent_at) DESC
       LIMIT 1`);
    const top = r.rows[0];
    if (!top) return null;
    const msgs = await this.chatMessages(top.chat_id, 40);
    return { chatId: top.chat_id, title: top.chat_title, waiting: top.waiting, messages: msgs };
  }

  // ── Persistent memory (survives restarts) ──────────────────────────────
  async addMemory(category, content) {
    const r = await this.pool.query(
      `INSERT INTO memory (category, content) VALUES ($1,$2) RETURNING id`, [category || "note", content]);
    return r.rows[0].id;
  }
  async memories(limit = 50) {
    const r = await this.pool.query(`SELECT id, category, content, created_at FROM memory ORDER BY created_at DESC LIMIT $1`, [limit]);
    return r.rows;
  }
  async deleteMemory(id) { const r = await this.pool.query(`DELETE FROM memory WHERE id=$1`, [id]); return r.rowCount > 0; }
  async clearMemory() { const r = await this.pool.query(`DELETE FROM memory`); return r.rowCount; }

  async stats() {
    const r = await this.pool.query(
      `SELECT COUNT(*)::int AS total,
              COUNT(*) FILTER (WHERE deleted_at IS NOT NULL AND NOT is_outgoing)::int AS deleted,
              COUNT(*) FILTER (WHERE edited_at IS NOT NULL)::int AS edited,
              COUNT(DISTINCT chat_id)::int AS chats
       FROM messages`);
    return r.rows[0];
  }
}
