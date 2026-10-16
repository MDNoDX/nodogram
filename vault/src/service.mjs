// The vault: receives your Business bot's updates, keeps every message from
// your private chats, and tells you at once — with the original text and
// media — when someone deletes or edits a message they sent you.
//
// Only the owner's account is served: business connections from anyone else
// are ignored, and the bot answers no one but the owner.

import path from "node:path";
import { BotError } from "./telegram.mjs";
import { deletedNotice, editedNotice, labelFor, resendMethod, toRecord } from "./content.mjs";
import { Gemini, QuotaExceeded } from "./gemini.mjs";
import { AppBridge } from "./appbridge.mjs";

const ALLOWED_UPDATES = ["message", "business_connection", "business_message", "edited_business_message", "deleted_business_messages", "inline_query"];
const MAX_DOWNLOAD = 20 * 1024 * 1024;   // Bot API getFile limit

export class Vault {
  constructor({ config, db, bot, log = console }) {
    this.config = config;
    this.db = db;
    this.bot = bot;
    this.log = log;
    this.ownerConnections = new Map();   // connection id → is owner's
    this.running = false;
    this.ai = (config.geminiKeys && config.geminiKeys.length) ? new Gemini(config.geminiKeys) : null;
    this.app = new AppBridge(config.apiToken);   // live data from the running Nodogram app
    this.agentHistory = [];   // Gemini contents for the ongoing conversation
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  async run() {
    this.running = true;
    // Long polling and a webhook cannot both be active.
    await this.bot.call("deleteWebhook", { drop_pending_updates: false });
    await this.registerCommands();
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
    if (update.inline_query) return this.onInlineQuery(update.inline_query);
  }

  // ── Inline mode: @MDNoDX_bot <matn> anywhere → ready-to-send reply variants ──

  async onInlineQuery(iq) {
    if (iq.from?.id !== this.config.ownerId) {
      // Only the owner may use it; show nothing to anyone else.
      return this.bot.call("answerInlineQuery", { inline_query_id: iq.id, results: [], cache_time: 5, is_personal: true }).catch(() => {});
    }
    const q = (iq.query || "").trim();
    if (!this.ai) {
      return this.bot.call("answerInlineQuery", { inline_query_id: iq.id, cache_time: 10, is_personal: true,
        results: [{ type: "article", id: "off", title: "Nodik AI o'chirilgan",
          description: "Gemini kaliti sozlanmagan", input_message_content: { message_text: q } }] }).catch(() => {});
    }
    // Debounce: while the user is still typing, don't spend a model call.
    const now = Date.now();
    this._inlineCache = this._inlineCache || new Map();
    if (this._lastInlineAt && now - this._lastInlineAt < 1800 && !this._inlineCache.has(q || "__auto__")) {
      return this.bot.call("answerInlineQuery", { inline_query_id: iq.id, cache_time: 1, is_personal: true,
        results: [{ type: "article", id: "wait", title: q ? ("Yuborish: " + q.slice(0, 40)) : "Nodik tayyorlamoqda…",
          description: "Bir lahza…", input_message_content: { message_text: q } }] }).catch(() => {});
    }
    this._lastInlineAt = now;
    try {
      // Empty/short query → analyse the latest conversation and suggest replies.
      // Query with text → treat it as the user's goal for that reply.
      const convo = await this.db.latestConversation();
      const cacheKey = (q || "__auto__") + "|" + (convo ? convo.messages.length : 0);
      const cached = this._inlineCache.get(cacheKey);
      if (cached && now - cached.at < 300_000) return this.answerInline(iq.id, cached.variants, cached.who);

      let variants, who = "";
      if (convo && convo.messages.length) {
        who = convo.title;
        const transcript = convo.messages.map((m) => `${m.is_outgoing ? "Men" : who}: ${(m.text || "").slice(0, 300)}`).join("\n");
        const goal = q ? `\n\nMening maqsadim: ${q}` : "";
        const out = await this.ai.generate({
          system: "Sen foydalanuvchining yozishma yordamchisisan. Quyidagi haqiqiy suhbatni o'qib, foydalanuvchi (Men) endi yuborishi uchun 3 ta QISQA, tabiiy javob variantini yoz. Har biri alohida qatorda, raqamsiz, o'zbekcha (yoki suhbat tilida), hozirgi ohangga mos. Faqat yuborishga tayyor matnlarni ber — kirish so'zi, sarlavha yoki izoh yozma.",
          prompt: `Suhbat (${who} bilan):\n${transcript}${goal}`,
          temperature: 0.9,
        });
        variants = splitVariants(out);
      } else if (q) {
        const out = await this.ai.generate({
          system: "Foydalanuvchining maqsadi asosida yuborishga tayyor 3 ta qisqa javob variantini yoz. Har biri alohida qatorda, o'zbekcha, tabiiy. Faqat matnlarni ber — kirish so'zi yozma.",
          prompt: q, temperature: 0.9,
        });
        variants = splitVariants(out);
      } else {
        return this.bot.call("answerInlineQuery", { inline_query_id: iq.id, cache_time: 10, is_personal: true,
          results: [{ type: "article", id: "empty", title: "Hali yozishma yo'q", description: "Maqsad yozing: 'rahmat ayt', 'rad et'…",
            input_message_content: { message_text: q } }] }).catch(() => {});
      }
      if (variants && variants.length) this._inlineCache.set(cacheKey, { at: Date.now(), variants, who });
      return this.answerInline(iq.id, (variants && variants.length) ? variants : [q || "..."], who);
    } catch (error) {
      return this.bot.call("answerInlineQuery", { inline_query_id: iq.id, cache_time: 5, is_personal: true,
        results: [{ type: "article", id: "err", title: "AI hozir javob berolmadi",
          description: error instanceof QuotaExceeded ? "Kunlik limit tugadi" : "Qayta urinib ko'ring",
          input_message_content: { message_text: q } }] }).catch(() => {});
    }
  }

  async answerInline(id, variants, who = "") {
    const tag = who ? `${who}ga javob` : "Yuborish uchun bosing";
    const results = variants.slice(0, 5).map((text, i) => ({
      type: "article", id: "v" + i,
      title: text.slice(0, 70),
      description: tag,
      input_message_content: { message_text: text },
    }));
    return this.bot.call("answerInlineQuery", { inline_query_id: id, results, cache_time: 10, is_personal: true }).catch(() => {});
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
    // Watched person wrote to you → a quiet heads-up in the log channel.
    if (!record.isOutgoing && record.senderId) {
      const label = await this.db.isWatched(record.senderId);
      if (label !== null) {
        await this.archive(`👁 <b>${escape(label || record.senderName)}</b> sizga yozdi:\n${escape((record.text || labelFor(record) || "").slice(0, 400))}`);
      }
    }
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
      const mark = (await this.db.isWatched(record.senderId)) !== null ? "👁 " : "";
      const notice = mark + editedNotice(record.senderName || record.chatTitle, record.chatUsername, result.previous, record.text);
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
      // Malformed HTML → resend as plain text so the user still gets the answer.
      if (error instanceof BotError && error.code === 400 && /parse|entity|tag/i.test(error.message || "")) {
        const plain = String(html).replace(/<[^>]+>/g, "");
        try { await this.bot.call("sendMessage", { chat_id: this.config.ownerId, text: plain, link_preview_options: { is_disabled: true } }); return; }
        catch { /* fall through to the handler below */ }
      }
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
          "👋 Men <b>Nodik</b> — sizning shaxsiy Telegram yordamchingiz. Odamlarni chin ko'zdan baholayman, maslahat beraman va Telegramingizni boshqarishga yordamlashaman.\n\n" +
          "<b>Sozlash:</b> Telegram → Settings → Account → Chat automation → bu botni barcha 1-to-1 chatlarga qo'shing. Shunda odamlar o'chirgan/tahrirlagan habarlarni ushlaб qolaman.\n\n" +
          "Menga <b>oddiy tilda yozing</b> — komanda shart emas:\n" +
          "• “Hasan bilan chatimni tahlil qil, nima deb o'ylaysan?”\n" +
          "• “@username kim?” · “kim nimani o'chirdi?”\n" +
          "• “Dilnozaga 'rahmat, ertaga boraman' deb yubor”\n\n" +
          "<b>Qisqa komandalar:</b>\n" +
          "/analyze <i>ism</i> — odamni chuqur tahlil\n" +
          "/info <i>ism</i> — odam haqida ma'lumot\n" +
          "/myinfo — mening faoliyatim · /dashboard — panel\n" +
          "/track <i>ism</i> — kuzatuvga olish · /watched · /untrack\n" +
          "/memory — xotira · /diagnostics — holat\n" +
          "/image <i>tavsif</i> — rasm yaratish\n" +
          "/search <i>so'z</i> · /media · /status · /deleted · /reset\n\n" +
          "💡 Istalgan chatда <code>@MDNoDX_bot maqsad</code> yozsangiz — tayyor javob variantlari chiqadi.");
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
        if (!q) return this.notify("Usage: <code>/search words</code> — I search your kept messages.\n\n<i>Note: a bot can't search all of Telegram like MySearch (that needs a years-long private index). I search your own chats; for public channels/users by name, use Nodogram's global search.</i>");
        return this.runAgent(`Search my kept messages for: ${q}. Show the best matches with who said them.`);
      }
      case "/chats":
        return this.runAgent("List my chats you can analyse, with message counts.");
      case "/analyze":
        if (!arg) return this.notify("🔍 <b>Tahlil</b>\nBir odam bilan butun yozishmangizni o'qib, u haqida halol xulosa beraman.\n\nFoydalanish: <code>/analyze ism</code>\nMasalan: <code>/analyze Hasan</code> yoki <code>/analyze @username</code>\n\nYoki oddiy yozing: “Hasan bilan chatimni tahlil qil”.");
        return this.runAgent(`Deeply analyse my whole conversation with ${arg} and tell me honestly what to do next.`);
      case "/info":
        if (!arg) return this.notify("👤 <b>Ma'lumot</b>\nOdam haqida: ommaviy profil + siz bilan chatidagi munosabat.\n\nFoydalanish: <code>/info @username</code> · <code>/info ism</code> · <code>/info 123456789</code>");
        return this.runAgent(`Give me an honest profile of ${arg}: look up their public info, and read my chat with them. Tell me who they are and how they are with me.`);
      case "/myinfo":
        return this.runAgent("Summarise MY own activity: how many chats, messages kept, deletions and edits caught, and my most active chats.");
      case "/track":
        if (!arg) return this.notify("👁 <b>Kuzatuv</b>\nBir odamni kuzatuvga olaman — siz bilan chatda yozsa, tahrirlasa yoki o'chirsa, kanalingizga xabar beraman.\n\nFoydalanish: <code>/track @username</code> · <code>/track ism</code>\n\nℹ️ Bot faqat sizning chatingizdagi faollikni ko'radi. Boshqa odamning yashirin harakatlarini kuzata olmayman.");
        return this.runAgent(`Add ${arg} to my watchlist so I'm alerted when they write, edit or delete in our chat.`);
      case "/untrack":
        if (!arg) return this.notify("Foydalanish: <code>/untrack ism</code> — kimni kuzatuvdan chiqarishni yozing. Ro'yxat: /watched");
        return this.runAgent(`Remove ${arg} from my watchlist.`);
      case "/watched":
        return this.runAgent("Who is on my watchlist right now?");
      case "/memory": {
        const mem = await this.db.memories(50);
        if (!mem.length) return this.notify("🧠 <b>Xotira bo'sh</b>\nMen hali siz haqingizda hech narsa saqlamadim. “Buni eslab qol: …” deb yozsangiz, saqlab qo'yaman.\n\nTozalash: <code>/memory clear</code>");
        if (arg === "clear") { const n = await this.db.clearMemory(); return this.notify(`🧠 Xotira tozalandi (${n} ta yozuv o'chdi).`); }
        const del = (message.text || "").match(/\/memory\s+del\s+(\d+)/);
        if (del) { const ok = await this.db.deleteMemory(Number(del[1])); return this.notify(ok ? `🗑 #${del[1]} o'chirildi.` : "Topilmadi."); }
        const lines = mem.map((m) => `#${m.id} ${escape(m.content)}`);
        return this.notify("🧠 <b>Nodik eslab qolgan narsalar</b>\n\n" + lines.join("\n") + "\n\nO'chirish: <code>/memory del ID</code> · Hammasini: <code>/memory clear</code>");
      }
      case "/diagnostics":
        return this.diagnostics();
      case "/dashboard":
        return this.dashboard();
      case "/image": {
        const prompt = (message.text || "").slice("/image".length).trim();
        if (!prompt) return this.notify("🎨 <b>Rasm yaratish</b>\nFoydalanish: <code>/image tavsif</code>\nMasalan: <code>/image tog' cho'qqisida quyosh chiqishi, akvarel uslubida</code>\n\nYoki oddiy yozing: “tog' rasmini yarat”.");
        if (!this.ai) return this.notify("AI o'chirilgan.");
        await this.bot.call("sendChatAction", { chat_id: this.config.ownerId, action: "upload_photo" }).catch(() => {});
        try {
          const img = await this.ai.image(prompt);
          await this.bot.sendPhotoBuffer(this.config.ownerId, Buffer.from(img.data, "base64"), { caption: "🎨 " + escape(prompt.slice(0, 200)), mime: img.mime });
        } catch (e) {
          return this.notify(e instanceof QuotaExceeded ? `⏳ Rasm kvotasi barcha kalitlarda tugadi. ${escape(e.retryAfter)} dan keyin urinib ko'ring.` : "Rasm yaratilmadi: " + escape((e.message || "").slice(0, 120)));
        }
        return;
      }
      case "/media":
        return this.notify("🎬 <b>GIF va Stikerlar</b>\nGIF/sticker yuborish va tozalash <b>Nodogram ilovasida</b> (chat yozuv maydonidagi 😊 tugmasi).\n\nBotда: “oxirgi o'chirilgan rasmlarni ko'rsat” kabi so'rashingiz mumkin.");
      case "/reset":
        this.agentHistory = [];
        return this.notify("🧠 Conversation cleared.");
      default:
        // Anything that isn't a known command is talked to the AI agent, which
        // decides what to do (analyse, search, look up, draft, send…).
        return this.runAgent(message.text ?? "");
    }
  }

  /// Publishes the bot's command menu (what BotFather shows). Only commands
  /// that actually have handlers are listed — the menu never advertises a
  /// feature that is not implemented.
  async registerCommands() {
    const commands = [
      ["start", "Nodikni ishga tushirish"],
      ["help", "Barcha imkoniyatlar va qo'llanma"],
      ["search", "Saqlangan xabarlarni qidirish"],
      ["chats", "Suhbatlar ro'yxati"],
      ["myinfo", "Mening akkauntim (guruhlar, kanallar)"],
      ["info", "Odam yoki chat haqida ma'lumot"],
      ["track", "Kuzatuvga olish"],
      ["watched", "Kuzatuvlar ro'yxati"],
      ["analyze", "Suhbatni chuqur tahlil qilish"],
      ["dashboard", "Umumiy boshqaruv paneli"],
      ["memory", "Nodik xotirasi"],
      ["diagnostics", "Tizim va AI holatini tekshirish"],
      ["image", "Rasm yaratish (AI)"],
      ["media", "GIF va sticker haqida"],
      ["deleted", "O'chirilgan xabarlar arxivi"],
      ["status", "Bot va ulanish holati"],
      ["reset", "Suhbat kontekstini tozalash"],
    ].map(([command, description]) => ({ command, description }));
    try { await this.bot.call("setMyCommands", { commands }); this.log.info?.("[vault] command menu published"); }
    catch (error) { this.log.warn?.("[vault] setMyCommands failed:", error.message); }
  }

  /// Technical health — no secrets, keys shown only as count.
  async diagnostics() {
    const lines = ["🩺 <b>Tizim diagnostikasi</b>", ""];
    // AI
    lines.push(`<b>AI (Nodik)</b>: ${this.ai ? "yoqilgan ✅" : "o'chirilgan ❌"}`);
    if (this.ai) {
      lines.push(`• Kalitlar: ${this.ai.keys.length} ta sozlangan`);
      lines.push(`• Modellar: ${this.ai.models.join(" → ")}`);
      let aiState = "tekshirilmadi";
      try { await this.ai.generate({ system: "ping", prompt: "ok", temperature: 0 }); aiState = "ishlayapti ✅"; }
      catch (e) { aiState = e instanceof QuotaExceeded ? `kunlik limit tugadi (⏳ ${escape(e.retryAfter)})` : "xato: " + escape((e.message||"").slice(0,60)); }
      lines.push(`• Holat: ${aiState}`);
    }
    // Telegram
    const connections = await this.db.activeConnections().catch(() => []);
    lines.push("", `<b>Telegram</b>: bot ulanган ✅`);
    lines.push(`• Business ulanish: ${connections.length ? "faol ✅" : "yo'q ⚠️ (Chat automation sozlang)"}`);
    // App bridge
    const ping = await this.app.ping();
    lines.push("", `<b>Nodogram ilovasi</b>: ${ping && ping.ok ? (ping.signedIn ? "ochiq, login qilingan ✅" : "ochiq, login yo'q ⚠️") : "yopiq ❌ (/info, /search, /myinfo uchun oching)"}`);
    // DB
    let db = "ulanган ✅";
    try { await this.db.stats(); } catch { db = "xato ❌"; }
    lines.push("", `<b>Ma'lumotlar bazasi</b>: ${db}`);
    return this.notify(lines.join("\n"));
  }

  /// A compact overview the owner can glance at.
  async dashboard() {
    const s = await this.db.stats().catch(() => ({ total: 0, chats: 0, deleted: 0, edited: 0 }));
    const watched = await this.db.watched().catch(() => []);
    const mem = await this.db.memories(1000).catch(() => []);
    const connections = await this.db.activeConnections().catch(() => []);
    const lines = [
      "📊 <b>Nodik — Boshqaruv paneli</b>", "",
      `💬 Chatlar: <b>${s.chats}</b> · Saqlangan xabar: <b>${s.total}</b>`,
      `🗑 Ushlangan o'chirish: <b>${s.deleted}</b> · ✏️ Tahrir: <b>${s.edited}</b>`,
      `👁 Kuzatuvda: <b>${watched.length}</b> kishi` + (watched.length ? " (" + watched.slice(0,5).map((w)=>escape(w.label)).join(", ") + ")" : ""),
      `🧠 Xotira: <b>${mem.length}</b> ta yozuv`,
      `🤖 AI: ${this.ai ? "yoqilgan" : "o'chirilgan"} · Ulanish: ${connections.length ? "faol" : "yo'q"}`,
      "",
      "Tezkor: /diagnostics · /myinfo · /watched · /memory · /deleted",
    ];
    return this.notify(lines.join("\n"));
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
      { name: "my_summary", description: "The user's own stored activity: how many chats, messages kept, deletions and edits caught. Use for /myinfo questions about the user themself.", parameters: { type: "OBJECT", properties: {} } },
      { name: "watch_person", description: "Add someone to the watchlist so the user is alerted (in their log channel) when that person writes to, edits or deletes in THEIR chat with the user. Name is a stored chat name or @username.", parameters: { type: "OBJECT", properties: { name: { type: "STRING" } }, required: ["name"] } },
      { name: "unwatch_person", description: "Stop watching someone.", parameters: { type: "OBJECT", properties: { name: { type: "STRING" } }, required: ["name"] } },
      { name: "list_watched", description: "People currently on the watchlist.", parameters: { type: "OBJECT", properties: {} } },
      { name: "remember", description: "Save a lasting fact about the user, their projects, preferences or decisions, so it is remembered across restarts. Only save real, confirmed facts — not guesses.", parameters: { type: "OBJECT", properties: { content: { type: "STRING" }, category: { type: "STRING" } }, required: ["content"] } },
      { name: "generate_image", description: "Generate an original image from a text description and send it to the user. Use when the user asks to create/draw/make a picture ('rasm yarat', 'rasm chiz'). Describe the scene in detail in the prompt.", parameters: { type: "OBJECT", properties: { prompt: { type: "STRING" } }, required: ["prompt"] } },
      { name: "person_info", description: "Rich profile of a person from the user's logged-in Nodogram session: their public profile, the groups the user shares with them, their recent messages in those shared groups, and username history. Use a @username, name or numeric id. Needs the Nodogram app to be open.", parameters: { type: "OBJECT", properties: { who: { type: "STRING" } }, required: ["who"] } },
      { name: "my_info", description: "The user's own account picture from Nodogram: their groups, channels, groups they own, groups they left, and usernames. Needs the Nodogram app to be open.", parameters: { type: "OBJECT", properties: {} } },
      { name: "global_search", description: "Search Telegram beyond the user's private chats — public channels, groups, people by name, and messages — via the user's Nodogram session. Needs the Nodogram app to be open. (A bot alone cannot index all of Telegram.)", parameters: { type: "OBJECT", properties: { query: { type: "STRING" } }, required: ["query"] } },
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
      if (name === "my_summary") {
        const s = await this.db.stats();
        const chats = await this.db.chats(1000);
        return { chats_with: s.chats, messages_kept: s.total, deletions_caught: s.deleted, edits_caught: s.edited, top_chats: chats.slice(0, 15).map((c) => ({ name: c.chat_title, messages: c.messages })) };
      }
      if (name === "watch_person") {
        let id = null, label = null;
        const chat = await this.db.findChat(args.name);
        if (chat) { id = Number(chat.chat_id); label = chat.chat_title; }
        else {
          const r = await this.app.resolve(args.name);   // contacts / @username / name via the app
          if (r && r.found) { id = Number(r.userId); label = r.title || args.name; }
        }
        if (id === null) return { error: "could not find that person in your chats, contacts or by @username. Open Nodogram if it is closed." };
        await this.db.watch(id, { label });
        return { watching: label, note: "Siz bilan chatda yozsa/tahrirlasa/o'chirsa kanalga xabar beraman." };
      }
      if (name === "unwatch_person") {
        let id = null, label = args.name;
        const chat = await this.db.findChat(args.name);
        if (chat) { id = Number(chat.chat_id); label = chat.chat_title; }
        else { const r = await this.app.resolve(args.name); if (r && r.found) { id = Number(r.userId); label = r.title || args.name; } }
        if (id === null) return { error: "not found" };
        const ok = await this.db.unwatch(id);
        return { unwatched: ok, name: label };
      }
      if (name === "list_watched") {
        const rows = await this.db.watched();
        return { watching: rows.map((r) => ({ name: r.label, since: r.added_at })) };
      }
      if (name === "send_message") {
        const connections = await this.db.activeConnections();
        if (!connections.length) return { error: "no active business connection" };
        const chat = await this.db.findChat(args.name);
        if (!chat) return { error: "no such chat to send to" };
        await this.bot.call("sendMessage", { business_connection_id: connections[0].id, chat_id: Number(chat.chat_id), text: args.text });
        return { sent: true, to: chat.chat_title };
      }
      if (name === "generate_image") {
        if (!args.prompt || !args.prompt.trim()) return { error: "describe what to draw" };
        try {
          const img = await this.ai.image(args.prompt.trim());
          const buffer = Buffer.from(img.data, "base64");
          await this.bot.sendPhotoBuffer(this.config.ownerId, buffer, { caption: "🎨 " + escape(args.prompt.slice(0, 200)), mime: img.mime });
          return { sent: true, note: "Image delivered to the user." };
        } catch (e) {
          if (e instanceof QuotaExceeded) return { error: "image quota exhausted for all keys; try again in " + e.retryAfter };
          return { error: "image generation failed: " + (e.message || "").slice(0, 100) };
        }
      }
      if (name === "remember") {
        if (!args.content || !args.content.trim()) return { error: "nothing to remember" };
        const id = await this.db.addMemory(args.category || "note", args.content.trim());
        return { saved: true, id };
      }
      if (name === "person_info") return await this.app.info(args.who || "");
      if (name === "my_info") return await this.app.myInfo();
      if (name === "global_search") return await this.app.search(args.query || "");
      return { error: "unknown tool" };
    } catch (error) {
      return { error: error.message };
    }
  }

  async runAgent(text) {
    if (!this.ai) return this.notify("AI is off. Add a Gemini key in Nodogram → Settings → AI Assistant.");
    if (!text.trim()) return this.notify("Menga oddiy tilda yozing — chatlaringizni tahlil qilaman, odamni o'rganaman, javob yozaman yoki yuboraman.");
    await this.bot.call("sendChatAction", { chat_id: this.config.ownerId, action: "typing" }).catch(() => {});
let system = [
      "Sening isming Nodik — foydalanuvchining shaxsiy aqlli yordamchisi. Egang — Nodirbek. U bilan har doim O'ZBEK TILIDA (lotin), tabiiy va samimiy gaplash.",
      "Doim o'zbekcha javob ber. Faqat foydalanuvchining o'zi boshqa tilni so'rasa yoki yozsa, o'sha tilda javob ber. Komanda shart emas — oddiy suhbat kifoya.",
      "Sen xushomadchi emas, halol va o'tkir tahlilchisan: odamlarni ularning haqiqiy xabarlari asosida baholaysan, ko'pchilik sezmaydigan naqshlarni ko'rsatasan, va aniq, rost xulosa hamda eng yaxshi keyingi qadamni aytasan — quruq ko'ngilxushlik emas.",
      "You control the user's own Telegram through tools: understand people from their chats, search their kept messages, report what others deleted or edited, look up a public @username, summarise the user's own activity, keep a watchlist, draft replies in the user's own voice, and — only when the user explicitly asks — send a message as them.",
      "Ground every claim about a person in real messages (fetch them with tools first); never invent. When you analyse someone, cover how they feel toward the user, their interest trend, their personality and communication style, what is waiting for a reply, and concrete next moves.",
      "For richer questions you can reach the user's logged-in Nodogram session with person_info (someone's profile + shared groups + their messages there + username history), my_info (the user's own groups/channels/owned/left/usernames) and global_search (public channels, groups, people, messages across Telegram). These need the Nodogram app open on the Mac — if a call comes back offline, tell the user to open Nodogram, and meanwhile answer from your own stored private-chat data.",
      "Everything you surface is what Telegram already shows the user from their own account — their chats, their groups, and the public side of people they share groups with. You never fabricate a person's whereabouts or activity you cannot actually see.",
      "send_message'dan oldin: foydalanuvchi aynan o'sha matnni aynan o'sha odamga yuborishni so'raganiga amin bo'l; shubha bo'lsa, avval qoralamani ko'rsatib so'ra.",
      "MUHIM: javoblaringni toza yoz. Markdown ishlatsang oddiy ishlat (**qalin**, - ro'yxat). Javob o'zbekcha, qisqa va aniq bo'lsin.",
      "Agar foydalanuvchi haqida muhim, tasdiqlangan fakt bilsang (afzallik, loyiha, qaror), uni remember bilan saqla — faqat haqiqiy faktlarni, taxminni emas.",
    ].join(" ");
    try {
      const mem = await this.db.memories(25);
      if (mem.length) system += "\n\nNodik eslab qolgan faktlar (foydalanuvchi haqida):\n" + mem.map((m) => `- ${m.content}`).join("\n");
    } catch {}
    this.agentHistory.push({ role: "user", parts: [{ text }] });
    if (this.agentHistory.length > 24) this.agentHistory = this.agentHistory.slice(-24);
    try {
      for (let step = 0; step < 4; step++) {
        const content = await this.ai.turn({ system, contents: this.agentHistory, tools: this.agentTools });
        const parts = content.parts || [];
        const calls = parts.filter((p) => p.functionCall).map((p) => p.functionCall);
        if (calls.length) {
          // Push the model's turn VERBATIM — Gemini 3.x attaches a
          // thoughtSignature to each functionCall part, and it must be sent
          // back unchanged or the next turn fails ("missing thought_signature").
          this.agentHistory.push({ role: content.role || "model", parts });
          const responses = [];
          for (const call of calls) {
            const result = await this.runTool(call.name, call.args || {});
            responses.push({ functionResponse: { name: call.name, response: result } });
            if (call.name === "send_message") await this.bot.call("sendChatAction", { chat_id: this.config.ownerId, action: "typing" }).catch(() => {});
          }
          this.agentHistory.push({ role: "user", parts: responses });
          continue;
        }
        const answer = parts.map((p) => p.text).filter(Boolean).join("").trim();
        this.agentHistory.push({ role: content.role || "model", parts: parts.length ? parts : [{ text: answer || "…" }] });
        return this.notify(answer ? toTelegramHTML(answer) : "Tushunmadim, qayta yozing.");
      }
      return this.notify("Juda ko'p qadam bo'ldi — savolni soddalashtiring.");
    } catch (error) {
      if (error instanceof QuotaExceeded) {
        this.agentHistory.pop();   // don't keep the unanswered turn
        return this.notify(`⏳ Bugungi bepul Gemini limiti tugadi (yangi kalitlar uchun kuniga ~20 so'rov). Taxminan <b>${escape(error.retryAfter)}</b> dan keyin tiklanadi.\n\nKo'proq ishlatish uchun: Nodogram → Settings → AI Assistant'ga yana bitta bepul Gemini kaliti qo'shing — men ularni navbat bilan ishlataman (har biri +20 so'rov/kun).`);
      }
      return this.notify("AI error: " + escape(error.message));
    }
  }
}

const escape = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// Turns the model's lines into clean send-ready reply options: strips bullets/
// numbering and quotes, and drops preamble/heading lines (e.g. "Mana 3 ta:").
function splitVariants(out) {
  return String(out || "").split(/\n+/)
    .map((l) => l.replace(/^\s*[-*\d.)\]]+\s*/, "").replace(/^["'“‘]|["'”’]$/g, "").trim())
    .filter((l) => l.length > 1 && !/[:：]\s*$/.test(l) && !/^(mana|quyida|variant|javob variant)/i.test(l))
    .slice(0, 5);
}

// Converts the AI's Markdown into the small HTML subset Telegram renders, so
// answers arrive tidy instead of showing raw **, ### and - markers.
function toTelegramHTML(md) {
  if (!md) return "";
  let s = escape(md);
  s = s.replace(/```[a-zA-Z]*\n?([\s\S]*?)```/g, (_, c) => `<pre>${c.replace(/\n+$/, "")}</pre>`);
  s = s.replace(/`([^`\n]+)`/g, "<code>$1</code>");
  s = s.replace(/^\s{0,3}#{1,6}\s*(.+?)\s*$/gm, "<b>$1</b>");
  s = s.replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>");
  s = s.replace(/__([^_\n]+)__/g, "<b>$1</b>");
  s = s.replace(/^\s*[-*•]\s+/gm, "• ");
  s = s.replace(/\[([^\]]+)\]\((https?:[^)]+)\)/g, '<a href="$2">$1</a>');
  // Leftover lone * or _ used for emphasis → italics (conservative).
  s = s.replace(/(^|[\s(])\*([^*\n]{1,80}?)\*(?=[\s.,!?)]|$)/g, "$1<i>$2</i>");
  return s.replace(/\n{3,}/g, "\n\n").trim();
}
