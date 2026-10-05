import { test } from "node:test";
import assert from "node:assert/strict";
import { toRecord, deletedNotice, mediaOf, parseEnvForTest } from "./helpers.mjs";
import { Vault } from "../src/service.mjs";

const OWNER = 1255719279;

class FakeDB {
  constructor() { this.messages = new Map(); this.connections = new Map(); this.state = {}; }
  key(c, m) { return `${c}:${m}`; }
  async getState(k, d) { return this.state[k] ?? d; }
  async setState(k, v) { this.state[k] = String(v); }
  async saveConnection(c) { this.connections.set(c.id, c.user.id); }
  async connectionOwner(id) { return this.connections.get(id) ?? null; }
  async activeConnections() { return [...this.connections.keys()]; }
  async saveMessage(r) {
    const k = this.key(r.chatId, r.messageId);
    if (!this.messages.has(k)) this.messages.set(k, { chat_id: r.chatId, message_id: r.messageId, text: r.text,
      sender_name: r.senderName, chat_title: r.chatTitle, chat_username: r.chatUsername, is_outgoing: r.isOutgoing,
      media_kind: r.mediaKind, file_id: r.fileId, local_path: null, sent_at: new Date(r.date * 1000), deleted_at: null });
  }
  async setLocalPath() {}
  async saveEdit(c, m, text) {
    const row = this.messages.get(this.key(c, m));
    if (!row) return { known: false, previous: null };
    const previous = row.text === text ? null : row.text;
    row.text = text;
    return { known: true, previous };
  }
  async markDeleted(c, ids) {
    const out = [];
    for (const id of ids) {
      const row = this.messages.get(this.key(c, id));
      if (row && !row.deleted_at) { row.deleted_at = new Date(); out.push(row); }
    }
    return out;
  }
  async markNotified() {}
}

class FakeBot {
  constructor() { this.sent = []; }
  async call(method, params) {
    if (method === "getBusinessConnection") return { id: params.business_connection_id, user: { id: 999 } };
    this.sent.push({ method, params });
    return {};
  }
  async download() { return null; }
  async upload() { return {}; }
}

const make = () => {
  const db = new FakeDB(), bot = new FakeBot();
  const vault = new Vault({ config: { ownerId: OWNER, mediaDir: "/tmp/x", notifyEdits: true }, db, bot, log: {} });
  return { db, bot, vault };
};

const msg = (id, text, from = { id: 42, first_name: "Nodir" }, extra = {}) => ({
  business_connection_id: "c1", message_id: id, date: 1_760_000_000, chat: { id: 42, type: "private", first_name: "Nodir" },
  from, text, ...extra,
});

test("connections from other accounts are ignored", async () => {
  const { db, bot, vault } = make();
  await vault.handle({ business_connection: { id: "evil", user: { id: 7 }, user_chat_id: 7, date: 1, is_enabled: true } });
  assert.equal(db.connections.size, 0);
  assert.equal(bot.sent.length, 0);
  await vault.handle({ business_message: { ...msg(1, "hi"), business_connection_id: "evil" } });
  assert.equal(db.messages.size, 0, "messages through a foreign connection are not stored");
});

test("a message someone deletes comes back to the owner with its text", async () => {
  const { bot, vault } = make();
  await vault.handle({ business_connection: { id: "c1", user: { id: OWNER }, user_chat_id: OWNER, date: 1, is_enabled: true } });
  await vault.handle({ business_message: msg(10, "Ertaga soat 10 da <keling>") });
  bot.sent = [];
  await vault.handle({ deleted_business_messages: { business_connection_id: "c1", chat: { id: 42 }, message_ids: [10] } });
  assert.equal(bot.sent.length, 1);
  assert.equal(bot.sent[0].method, "sendMessage");
  assert.equal(bot.sent[0].params.chat_id, OWNER);
  assert.match(bot.sent[0].params.text, /Nodir/);
  assert.match(bot.sent[0].params.text, /Ertaga soat 10 da &lt;keling&gt;/);
});

test("the owner's own deletions raise no alert", async () => {
  const { bot, vault } = make();
  await vault.handle({ business_connection: { id: "c1", user: { id: OWNER }, user_chat_id: OWNER, date: 1, is_enabled: true } });
  await vault.handle({ business_message: msg(11, "mine", { id: OWNER, first_name: "Me" }) });
  bot.sent = [];
  await vault.handle({ deleted_business_messages: { business_connection_id: "c1", chat: { id: 42 }, message_ids: [11] } });
  assert.equal(bot.sent.length, 0);
});

test("deleted photos are re-sent with the notice as caption", async () => {
  const { bot, vault } = make();
  await vault.handle({ business_connection: { id: "c1", user: { id: OWNER }, user_chat_id: OWNER, date: 1, is_enabled: true } });
  await vault.handle({ business_message: msg(12, undefined, undefined,
    { caption: "look", photo: [{ file_id: "small", file_unique_id: "s" }, { file_id: "big", file_unique_id: "b", file_size: 1000 }] }) });
  bot.sent = [];
  await vault.handle({ deleted_business_messages: { business_connection_id: "c1", chat: { id: 42 }, message_ids: [12] } });
  assert.equal(bot.sent[0].method, "sendPhoto");
  assert.equal(bot.sent[0].params.photo, "big");
  assert.match(bot.sent[0].params.caption, /look/);
});

test("edits notify with before and after", async () => {
  const { bot, vault } = make();
  await vault.handle({ business_connection: { id: "c1", user: { id: OWNER }, user_chat_id: OWNER, date: 1, is_enabled: true } });
  await vault.handle({ business_message: msg(13, "5 da") });
  bot.sent = [];
  await vault.handle({ edited_business_message: { ...msg(13, "6 da"), edit_date: 1_760_000_100 } });
  assert.match(bot.sent[0].params.text, /Before:.*5 da/s);
  assert.match(bot.sent[0].params.text, /Now:.*6 da/s);
});

test("the bot is silent to everyone but the owner", async () => {
  const { bot, vault } = make();
  await vault.handle({ message: { from: { id: 5 }, chat: { id: 5 }, text: "/status" } });
  assert.equal(bot.sent.length, 0);
});

test("media picks the largest photo and labels kinds", () => {
  assert.equal(mediaOf({ photo: [{ file_id: "a" }, { file_id: "b" }] }).fileId, "b");
  assert.equal(mediaOf({ voice: { file_id: "v" } }).label, "Voice message");
  assert.equal(toRecord(msg(1, "x", { id: OWNER }), OWNER).isOutgoing, true);
  assert.match(deletedNotice({ sender_name: "A&B", text: "<b>", sent_at: new Date(), deleted_at: new Date() }), /A&amp;B/);
  assert.deepEqual(parseEnvForTest("# c\nA=1\nB=\"two\"\n"), { A: "1", B: "two" });
});
