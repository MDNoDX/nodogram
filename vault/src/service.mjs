// The vault: receives your Business bot's updates, keeps every message from
// your private chats, and tells you at once — with the original text and
// media — when someone deletes or edits a message they sent you.
//
// Only the owner's account is served: business connections from anyone else
// are ignored, and the bot answers no one but the owner.

import path from "node:path";
import { BotError } from "./telegram.mjs";
import { deletedNotice, editedNotice, labelFor, resendMethod, toRecord } from "./content.mjs";
import { Gemini } from "./gemini.mjs";

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
    this.ai = config.geminiKey ? new Gemini(config.geminiKey) : null;
    this.agentHistory = [];   // Gemini contents for the ongoing conversation
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
    if (!record.isOutgoing && result.previous !== null) {
      const notice = editedNotice(record.senderName || record.chatTitle, record.chatUsername, result.previous, record.text);
      await this.archive(notice);
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

  /// A deleted message goes only to the log channel (not the owner's DM):
  /// the original content, re-sent, with a note of who deleted it and when.
  async sendDeleted(row) {
    const text = deletedNotice(row);
    if (!this.config.logChannel) return;
    const resend = row.media_kind ? resendMethod(row.media_kind) : null;
    if (!resend) { await this.archive(text); return; }
    const [method, field] = resend;
    const fits = text.length <= 1000 && !["sticker", "video_note"].includes(row.media_kind);
    const params = { chat_id: this.config.logChannel, ...(fits ? { caption: text, parse_mode: "HTML" } : {}) };
    try {
      await this.bot.call(method, { ...params, [field]: row.file_id });
    } catch (error) {
      if (row.local_path) {
        try { await this.bot.upload(method, field, row.local_path, params); }
        catch (uploadError) { this.log.warn?.("[vault] re-upload failed:", uploadError.message); await this.archive(text); }
      } else {
        this.log.warn?.("[vault] media resend failed:", error.message);
        await this.archive(text);
      }
    }
    if (!fits) await this.archive(text);
  }

  // ── Talking to the owner ──────────────────────────────────────────────────

  /// Posts to the owner's private log channel (the "memories" archive), if set.
  async archive(html, { media = null } = {}) {
    if (!this.config.logChannel) return;
    try {
      if (media) {
        const [method, field] = media.resend;
        await this.bot.call(method, { chat_id: this.config.logChannel, [field]: media.fileId,
          ...(media.caption ? { caption: media.caption, parse_mode: "HTML" } : {}) });
        if (!media.caption) await this.bot.call("sendMessage", { chat_id: this.config.logChannel, text: html, parse_mode: "HTML", link_preview_options: { is_disabled: true } });
      } else {
        await this.bot.call("sendMessage", { chat_id: this.config.logChannel, text: html, parse_mode: "HTML", link_preview_options: { is_disabled: true } });
      }
    } catch (error) {
      this.log.warn?.("[vault] archive to channel failed:", error.message);
    }
  }

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
          "<b>Set up:</b> Telegram → Settings → Account → Chat automation (older apps: Telegram Business → Chatbots) → add this bot for all 1-to-1 chats.\n\n" +
          "Just write to me in plain language — I control your Telegram:\n\n" +
          "• “Hasan bilan chatimni tahlil qil, nima deb o'ylaysan?”\n" +
          "• “@username kim, ma'lumot ber”\n" +
          "• “Aliga shanbaga uchrashuv taklif qilib yoz”\n" +
          "• “kim nimani o'chirdi?”, “kim menga yozmoqchi bo'ldi?”\n" +
          "• “Dilnozaga 'rahmat, ertaga boraman' deb yubor”\n\n" +
          "/reset — forget our conversation · /status · /deleted · /chats");
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
      case "/chats": {
        const chats = await this.db.chats(30);
        if (!chats.length) return this.notify("No private chats kept yet.");
        const lines = chats.map((c) => `• <b>${escape(c.chat_title || "Chat")}</b> — ${c.messages} msgs`);
        return this.notify("Chats I can analyse:\n" + lines.join("\n"));
      }
      case "/ai": {
        const q = (message.text ?? "").slice(3).trim();
        if (!this.ai) return this.notify("AI is off. Add a Gemini key in Nodogram → Settings → AI Assistant (it is shared with the bot).");
        if (!q) return this.notify("Ask me anything about your chats, e.g. <code>/ai who is waiting for my reply?</code>");
        await this.bot.call("sendChatAction", { chat_id: this.config.ownerId, action: "typing" }).catch(() => {});
        try {
          const context = await this.db.recentAcross(120);
          const transcript = context.map((m) => `[${m.chat_title}] ${m.is_outgoing ? "Me" : "Them"}: ${(m.text || "").slice(0, 300)}`).join("\n");
          const answer = await this.ai.generate({
            system: "You are the user's sharp, warm personal assistant inside Telegram. Answer about their private chats using only the transcript. Be concise, honest and practical. Reply in the user's language (Uzbek Latin if unsure).",
            prompt: `Recent messages across chats (latest last):\n${transcript}\n\nQuestion: ${q}`,
          });
          return this.notify(escape(answer));
        } catch (error) {
          return this.notify("AI error: " + escape(error.message));
        }
      }
      case "/analyze": {
        const name = (message.text ?? "").slice("/analyze".length).trim();
        if (!this.ai) return this.notify("AI is off. Add a Gemini key in Nodogram → Settings → AI Assistant.");
        if (!name) return this.notify("Usage: <code>/analyze name</code> — try /chats to see names.");
        const chat = await this.db.findChat(name);
        if (!chat) return this.notify(`No kept chat matches “${escape(name)}”. Try /chats.`);
        await this.bot.call("sendChatAction", { chat_id: this.config.ownerId, action: "typing" }).catch(() => {});
        try {
          const msgs = await this.db.chatMessages(chat.chat_id, 300);
          const transcript = msgs.map((m) => `${m.is_outgoing ? "Me" : "Them"}: ${(m.text || (m.media_kind ? "["+m.media_kind+"]" : "")).slice(0, 400)}${m.deleted_at ? " (deleted)" : ""}`).join("\n");
          const answer = await this.ai.generate({
            system: "You are a thoughtful relationship and communication coach. Read the real chat between Me and Them and help Me understand this person — honestly, kindly, grounded in the messages, never manipulative. Cover: how they feel toward Me, their interest level and whether it's rising or cooling, their personality and communication style, anything waiting for a reply, and 3-5 concrete tips. Reply in Uzbek Latin unless the chat is clearly another language.",
            prompt: `Chat with ${chat.chat_title} (latest last):\n${transcript}`,
          });
          return this.notify(`<b>${escape(chat.chat_title)}</b>\n\n` + escape(answer));
        } catch (error) {
          return this.notify("AI error: " + escape(error.message));
        }
      }
      case "/draft": {
        const rest = (message.text ?? "").slice("/draft".length).trim();
        if (!this.ai) return this.notify("AI is off. Add a Gemini key in Nodogram → Settings → AI Assistant.");
        const [name, goal] = rest.split("|").map((s) => s.trim());
        if (!name || !goal) return this.notify("Usage: <code>/draft name | your goal</code>\ne.g. <code>/draft Ali | shanbaga uchrashuv taklif qil</code>");
        const chat = await this.db.findChat(name);
        if (!chat) return this.notify(`No kept chat matches “${escape(name)}”. Try /chats.`);
        await this.bot.call("sendChatAction", { chat_id: this.config.ownerId, action: "typing" }).catch(() => {});
        try {
          const msgs = await this.db.chatMessages(chat.chat_id, 120);
          const transcript = msgs.map((m) => `${m.is_outgoing ? "Me" : "Them"}: ${(m.text || "").slice(0, 300)}`).join("\n");
          const draft = await this.ai.generate({
            system: "Write one message for Me to send, in Me's own style and language as seen in the chat. Honour the goal, fit the conversation, be warm and natural, never robotic. Reply with the message text only.",
            prompt: `Chat with ${chat.chat_title} (latest last):\n${transcript}\n\nMy goal: ${goal}`,
          });
          return this.notify(`✍️ Draft for <b>${escape(chat.chat_title)}</b> — copy, edit and send it yourself:\n\n<code>${escape(draft)}</code>`);
        } catch (error) {
          return this.notify("AI error: " + escape(error.message));
        }
      }
      case "/reset":
        this.agentHistory = [];
        return this.notify("🧠 Conversation cleared.");
      default:
        // Anything that isn't a known command is talked to the AI agent, which
        // decides what to do (analyse, search, look up, draft, send…).
        return this.runAgent(message.text ?? "");
    }
  }

  // ── Conversational agent ────────────────────────────────────────────────

  get agentTools() {
    return [
      { name: "list_chats", description: "List the user's private chats the vault has stored, with message counts.", parameters: { type: "OBJECT", properties: {} } },
      { name: "get_chat_messages", description: "Get recent messages of one chat for analysis. Use the person's name.", parameters: { type: "OBJECT", properties: { name: { type: "STRING" }, limit: { type: "INTEGER" } }, required: ["name"] } },
      { name: "search_messages", description: "Search all stored messages for words.", parameters: { type: "OBJECT", properties: { query: { type: "STRING" } }, required: ["query"] } },
      { name: "recent_deletions", description: "Messages others deleted, newest first.", parameters: { type: "OBJECT", properties: { limit: { type: "INTEGER" } } } },
      { name: "recent_edits", description: "Messages others edited, newest first.", parameters: { type: "OBJECT", properties: { limit: { type: "INTEGER" } } } },
      { name: "lookup_user", description: "Public Telegram info for a @username or t.me link.", parameters: { type: "OBJECT", properties: { username: { type: "STRING" } }, required: ["username"] } },
      { name: "send_message", description: "Send a message AS the user to one of their private chats, via the business connection. ONLY call this when the user, in their most recent message, explicitly asked to send this specific text to this specific person. Never invent a send.", parameters: { type: "OBJECT", properties: { name: { type: "STRING" }, text: { type: "STRING" } }, required: ["name", "text"] } },
    ];
  }

  async runTool(name, args) {
    try {
      if (name === "list_chats") {
        const chats = await this.db.chats(40);
        return { chats: chats.map((c) => ({ name: c.chat_title, messages: c.messages })) };
      }
      if (name === "get_chat_messages") {
        const chat = await this.db.findChat(args.name);
        if (!chat) return { error: "no such chat" };
        const msgs = await this.db.chatMessages(chat.chat_id, Math.min(args.limit || 200, 400));
        return { chat: chat.chat_title, messages: msgs.map((m) => ({ who: m.is_outgoing ? "Me" : "Them", text: m.text || (m.media_kind ? `[${m.media_kind}]` : ""), at: m.sent_at, deleted: !!m.deleted_at, edited: !!m.edited_at })) };
      }
      if (name === "search_messages") {
        const rows = await this.db.search(args.query, 20);
        return { results: rows.map((r) => ({ chat: r.chat_title, who: r.is_outgoing ? "Me" : "Them", text: r.text, deleted: !!r.deleted_at })) };
      }
      if (name === "recent_deletions") {
        const rows = await this.db.deleted({ limit: Math.min(args.limit || 10, 30) });
        return { deleted: rows.map((r) => ({ chat: r.chat_title, who: r.sender_name, text: r.text || `[${r.media_kind}]`, at: r.deleted_at })) };
      }
      if (name === "recent_edits") {
        const rows = await this.db.edited({ limit: Math.min(args.limit || 10, 30) });
        return { edited: rows.map((r) => ({ chat: r.chat_title, who: r.sender_name, now: r.text })) };
      }
      if (name === "lookup_user") {
        const handle = String(args.username).replace(/^.*t\.me\//, "").replace(/^@/, "").trim();
        try {
          const chat = await this.bot.call("getChat", { chat_id: "@" + handle });
          return { id: chat.id, name: [chat.first_name, chat.last_name].filter(Boolean).join(" ") || chat.title, username: chat.username, bio: chat.bio, description: chat.description, type: chat.type };
        } catch (e) { return { error: "not found or private: " + e.message }; }
      }
      if (name === "send_message") {
        const connections = await this.db.activeConnections();
        if (!connections.length) return { error: "no active business connection" };
        const chat = await this.db.findChat(args.name);
        if (!chat) return { error: "no such chat to send to" };
        await this.bot.call("sendMessage", { business_connection_id: connections[0].id, chat_id: Number(chat.chat_id), text: args.text });
        return { sent: true, to: chat.chat_title };
      }
      return { error: "unknown tool" };
    } catch (error) {
      return { error: error.message };
    }
  }

  async runAgent(text) {
    if (!this.ai) return this.notify("AI is off. Add a Gemini key in Nodogram → Settings → AI Assistant.");
    if (!text.trim()) return this.notify("Menga oddiy tilda yozing — chatlaringizni tahlil qilaman, odamni o'rganaman, javob yozaman yoki yuboraman.");
    await this.bot.call("sendChatAction", { chat_id: this.config.ownerId, action: "typing" }).catch(() => {});
    const system = [
      "You are the user's personal Telegram AI assistant, speaking with them privately in their bot.",
      "Talk naturally in the user's language (Uzbek Latin if unsure). You control their Telegram through tools:",
      "understand people from their chats, search, report what others deleted/edited, look up public @usernames,",
      "draft replies in the user's own style, and — only when the user clearly asks — send a message as them.",
      "Be warm, sharp, honest and concise. Ground claims in real messages (use tools to fetch them); never invent.",
      "Before sending anything with send_message, make sure the user explicitly asked to send that exact message to",
      "that exact person in their latest request; if unsure, ask them to confirm instead of sending.",
    ].join(" ");
    this.agentHistory.push({ role: "user", parts: [{ text }] });
    if (this.agentHistory.length > 24) this.agentHistory = this.agentHistory.slice(-24);
    try {
      for (let step = 0; step < 6; step++) {
        const content = await this.ai.turn({ system, contents: this.agentHistory, tools: this.agentTools });
        const call = content.parts?.find((p) => p.functionCall)?.functionCall;
        if (call) {
          this.agentHistory.push({ role: "model", parts: [{ functionCall: call }] });
          const result = await this.runTool(call.name, call.args || {});
          this.agentHistory.push({ role: "user", parts: [{ functionResponse: { name: call.name, response: result } }] });
          if (call.name === "send_message") await this.bot.call("sendChatAction", { chat_id: this.config.ownerId, action: "typing" }).catch(() => {});
          continue;
        }
        const answer = (content.parts || []).map((p) => p.text).filter(Boolean).join("").trim();
        this.agentHistory.push({ role: "model", parts: [{ text: answer || "…" }] });
        return this.notify(escape(answer || "Tushunmadim, qayta yozing."));
      }
      return this.notify("Juda ko'p qadam bo'ldi — savolni soddalashtiring.");
    } catch (error) {
      return this.notify("AI error: " + escape(error.message));
    }
  }
}

const escape = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
