// The vault: receives your Business bot's updates, keeps every message from
// your private chats, and tells you at once — with the original text and
// media — when someone deletes or edits a message they sent you.
//
// Only the owner's account is served: business connections from anyone else
// are ignored, and the bot answers no one but the owner.

import path from "node:path";
import { BotError } from "./telegram.mjs";
import { deletedNotice, editedNotice, labelFor, resendMethod, toRecord } from "./content.mjs";

const ALLOWED_UPDATES = ["message", "business_connection", "business_message", "edited_business_message", "deleted_business_messages"];
const MAX_DOWNLOAD = 20 * 1024 * 1024;   // Bot API getFile limit

export class Vault {
  constructor({ config, db, bot, log = console }) {
    this.config = config;
    this.db = db;
    this.bot = bot;
    this.log = log;
    this.ownerConnections = new Map();   // connection id → is owner's
    this.running = false;
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  async run() {
    this.running = true;
    // Long polling and a webhook cannot both be active.
    await this.bot.call("deleteWebhook", { drop_pending_updates: false });
    let offset = Number(await this.db.getState("offset", "0"));
    this.log.info?.("[vault] polling");
    while (this.running) {
      let updates = [];
      try {
        updates = await this.bot.call("getUpdates", { offset, timeout: 50, allowed_updates: ALLOWED_UPDATES });
      } catch (error) {
        this.log.error?.("[vault] getUpdates failed:", error.message);
        await new Promise((r) => setTimeout(r, 5000));
        continue;
      }
      for (const update of updates) {
        try {
          await this.handle(update);
        } catch (error) {
          this.log.error?.(`[vault] update ${update.update_id} failed:`, error);
        }
        offset = update.update_id + 1;
        await this.db.setState("offset", offset);
      }
    }
  }

  stop() { this.running = false; }

  async handle(update) {
    if (update.business_connection) return this.onConnection(update.business_connection);
    if (update.business_message) return this.onMessage(update.business_message);
    if (update.edited_business_message) return this.onEdit(update.edited_business_message);
    if (update.deleted_business_messages) return this.onDeleted(update.deleted_business_messages);
    if (update.message) return this.onDirect(update.message);
  }

  // ── Business updates ──────────────────────────────────────────────────────

  async onConnection(connection) {
    if (connection.user?.id !== this.config.ownerId) {
      this.log.warn?.(`[vault] ignored a business connection from user ${connection.user?.id}`);
      return;
    }
    await this.db.saveConnection(connection);
    this.ownerConnections.set(connection.id, true);
    await this.notify(connection.is_enabled
      ? "✅ <b>Nodogram Vault is connected.</b>\nMessages people delete or edit in your private chats will appear here, with what they said."
      : "⏸ Nodogram Vault was disconnected from your account.");
  }

  /** Whether a connection belongs to the owner, asking Telegram once if unknown. */
  async isOwnerConnection(id) {
    if (!id) return false;
    if (this.ownerConnections.has(id)) return this.ownerConnections.get(id);
    let owner = await this.db.connectionOwner(id);
    if (owner === null) {
      try {
        const connection = await this.bot.call("getBusinessConnection", { business_connection_id: id });
        if (connection.user?.id === this.config.ownerId) await this.db.saveConnection(connection);
        owner = connection.user?.id ?? null;
      } catch { owner = null; }
    }
    const ok = owner === this.config.ownerId;
    this.ownerConnections.set(id, ok);
    return ok;
  }

  async onMessage(message) {
    if (!(await this.isOwnerConnection(message.business_connection_id))) return;
    const record = toRecord(message, this.config.ownerId);
    await this.db.saveMessage(record);
    // Keep the media now: after a deletion it may no longer be downloadable.
    // Copy-protected content is never copied (Telegram API terms).
    if (record.fileId && !record.isProtected && record.fileSize <= MAX_DOWNLOAD) {
      const base = path.join(this.config.mediaDir, String(record.chatId), `${record.messageId}_${record.fileUniqueId}`);
      this.bot.download(record.fileId, base)
        .then((saved) => saved && this.db.setLocalPath(record.chatId, record.messageId, saved))
        .catch((error) => this.log.warn?.("[vault] download failed:", error.message));
    }
  }

  async onEdit(message) {
    if (!(await this.isOwnerConnection(message.business_connection_id))) return;
    const record = toRecord(message, this.config.ownerId);
    const result = await this.db.saveEdit(record.chatId, record.messageId, record.text,
      message.edit_date ?? Math.floor(Date.now() / 1000), message);
    if (!result.known) { await this.db.saveMessage(record); return; }
    if (this.config.notifyEdits && !record.isOutgoing && result.previous !== null) {
      await this.notify(editedNotice(record.senderName || record.chatTitle, record.chatUsername, result.previous, record.text));
    }
  }

  async onDeleted(event) {
    if (!(await this.isOwnerConnection(event.business_connection_id))) return;
    const rows = await this.db.markDeleted(event.chat.id, event.message_ids);
    // The owner deleting their own messages needs no alert.
    for (const row of rows.filter((r) => !r.is_outgoing)) {
      await this.sendDeleted(row);
      await this.db.markNotified(row.chat_id, row.message_id);
    }
    const unknown = event.message_ids.length - rows.length;
    if (unknown > 0) this.log.info?.(`[vault] ${unknown} deleted message(s) were never seen (sent before the vault started)`);
  }

  async sendDeleted(row) {
    const text = deletedNotice(row);
    const resend = row.media_kind ? resendMethod(row.media_kind) : null;
    if (!resend) return this.notify(text);
    const [method, field] = resend;
    // Captions are limited to 1024 characters; long texts go separately.
    const fits = text.length <= 1000 && !["sticker", "video_note"].includes(row.media_kind);
    const params = { chat_id: this.config.ownerId, ...(fits ? { caption: text, parse_mode: "HTML" } : {}) };
    try {
      await this.bot.call(method, { ...params, [field]: row.file_id });
    } catch (error) {
      if (row.local_path) {
        try { await this.bot.upload(method, field, row.local_path, params); }
        catch (uploadError) { this.log.warn?.("[vault] re-upload failed:", uploadError.message); }
      } else {
        this.log.warn?.("[vault] media resend failed:", error.message);
      }
    }
    if (!fits) await this.notify(text);
  }

  // ── Talking to the owner ──────────────────────────────────────────────────

  async notify(html) {
    try {
      await this.bot.call("sendMessage", {
        chat_id: this.config.ownerId, text: html, parse_mode: "HTML",
        link_preview_options: { is_disabled: true },
      });
    } catch (error) {
      if (error instanceof BotError && error.code === 403) {
        this.log.warn?.("[vault] the owner hasn't started the bot yet — open it in Telegram and press Start");
      } else {
        this.log.error?.("[vault] notify failed:", error.message);
      }
    }
  }

  async onDirect(message) {
    if (message.from?.id !== this.config.ownerId) return;   // private bot: silent to everyone else
    const [command, arg] = (message.text ?? "").trim().split(/\s+/, 2);
    switch (command) {
      case "/start":
      case "/help":
        return this.notify(
          "👋 <b>Nodogram Vault</b>\n" +
          "I keep the messages people send you in private chats. When someone deletes or edits one, I show you what it said — text, photos, voice and files.\n\n" +
          "<b>Set up:</b> Telegram → Settings → Telegram Business → Chatbots → add this bot, for all 1-to-1 chats.\n\n" +
          "/status — what's kept\n/deleted — the latest deletions\n/search <i>words</i> — search kept messages");
      case "/status": {
        const s = await this.db.stats();
        const connections = await this.db.activeConnections();
        return this.notify(
          `${connections.length ? "✅ Connected" : "⚠️ Not connected to your account yet"}\n` +
          `Kept: <b>${s.total}</b> messages in <b>${s.chats}</b> chats\nDeleted by others: <b>${s.deleted}</b>\nEdited: <b>${s.edited}</b>`);
      }
      case "/deleted": {
        const n = Math.min(Number(arg) || 5, 20);
        const rows = await this.db.deleted({ limit: n });
        if (!rows.length) return this.notify("Nothing deleted yet.");
        for (const row of rows.reverse()) await this.sendDeleted(row);
        return;
      }
      case "/search": {
        const q = (message.text ?? "").slice("/search".length).trim();
        if (!q) return this.notify("Usage: /search <i>words</i>");
        const rows = await this.db.search(q, 10);
        if (!rows.length) return this.notify("No kept message matches.");
        const lines = rows.map((r) => `• <b>${escape(r.sender_name || r.chat_title)}</b>: ${escape((r.text || labelFor(r)).slice(0, 160))}${r.deleted_at ? " 🗑" : ""}`);
        return this.notify(lines.join("\n"));
      }
      default:
        return this.notify("Commands: /status · /deleted · /search <i>words</i>");
    }
  }
}

const escape = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
