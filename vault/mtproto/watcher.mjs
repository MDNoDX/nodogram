// Nodik Watcher — a standalone MTProto user-session monitor.
//
// Runs as YOUR Telegram account (via the session string from login.mjs) and
// watches YOUR OWN incoming activity — the same things Telegram already shows
// you in the app — reporting each to your log channel through the bot:
//   • someone is TYPING to you, then sends nothing ("tried to write")
//   • someone sends you a message (optional, REPORT_MESSAGES=1)
//   • someone @mentions / replies to you in a group or channel you are in
//   • someone deletes a message (private or group) — with what it said
//   • someone edits a message — before and after
//   • someone views your story (checked every few minutes)
//   • someone becomes a mutual contact (≈ they added you back)
//
// It needs no Nodogram and, on a server, no Mac. It never touches anyone
// else's private data.

import { TelegramClient, Api } from "telegram";
import { StringSession } from "telegram/sessions/index.js";
import { loadEnv } from "./env.mjs";

const env = loadEnv();
const apiId = Number(env.API_ID);
const apiHash = env.API_HASH;
const session = env.MTPROTO_SESSION;
const botToken = env.BOT_TOKEN;
const channel = env.LOG_CHANNEL;
const reportMessages = env.REPORT_MESSAGES === "1" || env.REPORT_MESSAGES === "true";
const debug = env.DEBUG === "1" || env.DEBUG === "true";

if (!apiId || !apiHash || !session) {
  console.error("Missing API_ID / API_HASH / MTPROTO_SESSION in .env — run `node login.mjs` first.");
  process.exit(1);
}
if (!botToken || !channel) console.warn("[watcher] BOT_TOKEN / LOG_CHANNEL not set — events will only be logged to the console.");

const TYPING_SETTLE_MS = 8000;
const NAME_TTL_MS = 10 * 60 * 1000;
const STORY_POLL_MS = 5 * 60 * 1000;
const MSG_CACHE_CAP = 6000;     // recent messages kept to show deleted/edited text

const escape = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const nameCache = new Map();     // userId -> { html, at }
const titleCache = new Map();    // peerKey -> title
const typingState = new Map();   // userId -> { startAt, lastAt, timer }
const msgStore = new Map();      // key -> { text, fromId, title }
const seenStoryViewers = new Map(); // storyId -> Set(userId)
const knownMutuals = new Set();  // userIds already mutual at startup
let myId = 0;
let myUsernames = [];

async function report(html) {
  console.log("[watcher]", html.replace(/<[^>]+>/g, ""));
  if (!botToken || !channel) return;
  try {
    await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ chat_id: Number(channel), text: html, parse_mode: "HTML", link_preview_options: { is_disabled: true } }),
    });
  } catch (e) { console.error("[watcher] report failed:", e.message); }
}

const client = new TelegramClient(new StringSession(session), apiId, apiHash, { connectionRetries: 10, retryDelay: 2000 });

async function displayName(userId) {
  const key = String(userId);
  const hit = nameCache.get(key);
  if (hit && Date.now() - hit.at < NAME_TTL_MS) return hit.html;
  const idLink = `🆔 <a href="tg://user?id=${userId}">${userId}</a>`;
  let html = idLink;
  try {
    const e = await client.getEntity(userId);
    const full = [e.firstName, e.lastName].filter(Boolean).join(" ");
    const uname = e.username ? "@" + e.username : "";
    const label = [escape(full), uname ? `(${escape(uname)})` : ""].filter(Boolean).join(" ");
    if (label) html = `${label} · ${idLink}`;
  } catch { /* stranger → just the id */ }
  nameCache.set(key, { html, at: Date.now() });
  return html;
}

async function chatTitle(peer) {
  const key = peerKey(peer);
  if (titleCache.has(key)) return titleCache.get(key);
  let title = key;
  try {
    const e = await client.getEntity(peer);
    title = e.title || [e.firstName, e.lastName].filter(Boolean).join(" ") || (e.username ? "@" + e.username : key);
  } catch { /* keep key */ }
  titleCache.set(key, title);
  return title;
}

function peerKey(peer) {
  if (peer instanceof Api.PeerChannel || peer?.channelId) return "c" + (peer.channelId ?? peer);
  if (peer instanceof Api.PeerChat || peer?.chatId) return "g" + (peer.chatId ?? peer);
  if (peer instanceof Api.PeerUser || peer?.userId) return "u" + (peer.userId ?? peer);
  return String(peer);
}

function stamp() {
  return new Date().toLocaleString("en-GB", { hour12: false, timeZone: env.TZ || "Asia/Tashkent" });
}

// ── Typing ──────────────────────────────────────────────────────────────────
function typedSeconds(st) { return Math.max(1, Math.round((st.lastAt - st.startAt) / 1000) + 3); }

async function onTyping(userId) {
  const key = String(userId);
  const now = Date.now();
  let st = typingState.get(key);
  if (!st) st = { startAt: now, lastAt: now, timer: null };
  st.lastAt = now;
  if (st.timer) clearTimeout(st.timer);
  st.timer = setTimeout(async () => {
    typingState.delete(key);
    const name = await displayName(userId);
    await report(`👀 <b>${name}</b> sizga <b>~${typedSeconds(st)} soniya</b> yozdi, lekin yubormadi · ${escape(stamp())}`);
  }, TYPING_SETTLE_MS);
  typingState.set(key, st);
}

function cancelTyping(userId) {
  const st = typingState.get(String(userId));
  if (!st) return null;
  if (st.timer) clearTimeout(st.timer);
  typingState.delete(String(userId));
  return typedSeconds(st);
}

// ── Message store (so deletions/edits can show the text) ─────────────────────
function storeKey(isChannel, chanOrNull, msgId) { return isChannel ? `c${chanOrNull}:${msgId}` : `m${msgId}`; }

function remember(key, data) {
  msgStore.set(key, data);
  if (msgStore.size > MSG_CACHE_CAP) msgStore.delete(msgStore.keys().next().value);
}

function mentionsMe(m) {
  if (m?.mentioned) return true;
  const text = (m?.message || "").toLowerCase();
  return myUsernames.some((u) => text.includes("@" + u));
}

// Capture a message object (from any update) for later delete/edit lookup, and
// surface a mention if it targets you in a group/channel.
async function handleMessage(m) {
  if (!m || !m.peerId) return;
  const isChannel = m.peerId instanceof Api.PeerChannel;
  const isGroupish = isChannel || m.peerId instanceof Api.PeerChat;
  const chanId = isChannel ? Number(m.peerId.channelId) : null;
  const key = storeKey(isChannel, chanId, m.id);
  const fromId = m.fromId?.userId ? Number(m.fromId.userId) : (m.peerId.userId ? Number(m.peerId.userId) : null);
  remember(key, { text: m.message || "", fromId, title: titleCache.get(peerKey(m.peerId)) });

  if (!m.out && isGroupish && mentionsMe(m)) {
    const title = await chatTitle(m.peerId);
    const who = fromId ? await displayName(fromId) : "Kimdir";
    await report(`💬 <b>${who}</b> sizni <b>${escape(title)}</b>da esladi: ${escape((m.message || "").slice(0, 300))} · ${escape(stamp())}`);
  }
}

async function onDelete(key) {
  const rec = msgStore.get(key);
  if (!rec) return;   // we never saw it (sent before the watcher started)
  msgStore.delete(key);
  if (!rec.text) return;
  const who = rec.fromId ? await displayName(rec.fromId) : "Kimdir";
  const where = rec.title ? ` (<b>${escape(rec.title)}</b>)` : "";
  await report(`🗑 <b>${who}</b>${where} xabarini o'chirdi: ${escape(rec.text.slice(0, 400))} · ${escape(stamp())}`);
}

async function onEdit(m, isChannel) {
  if (!m || !m.peerId || m.out) return;
  const chanId = isChannel ? Number(m.peerId.channelId) : null;
  const key = storeKey(isChannel, chanId, m.id);
  const prev = msgStore.get(key);
  const now = m.message || "";
  remember(key, { text: now, fromId: prev?.fromId ?? (m.fromId?.userId ? Number(m.fromId.userId) : null), title: prev?.title });
  if (!prev || prev.text === now || !prev.text) return;
  const fromId = prev.fromId;
  const who = fromId ? await displayName(fromId) : "Kimdir";
  await report(`✏️ <b>${who}</b> xabarini tahrirladi:\nAvval: ${escape(prev.text.slice(0, 250))}\nKeyin: ${escape(now.slice(0, 250))} · ${escape(stamp())}`);
}

async function maybeNewMutual(userId) {
  if (!userId || knownMutuals.has(Number(userId))) return;
  try {
    const e = await client.getEntity(userId);
    if (e.mutualContact) {
      knownMutuals.add(Number(userId));
      const name = await displayName(userId);
      await report(`➕ <b>${name}</b> sizni kontaktiga qo'shdi (o'zaro kontakt) · ${escape(stamp())}`);
    }
  } catch { /* ignore */ }
}

// ── Update dispatch ──────────────────────────────────────────────────────────
client.addEventHandler(async (update) => {
  try {
    if (debug) console.log("[upd]", update?.className || update?.constructor?.name || typeof update);

    if (update instanceof Api.UpdateUserTyping) {
      if (!(update.action instanceof Api.SendMessageCancelAction)) await onTyping(update.userId);
      return;
    }

    // New messages (capture for delete/edit, detect mentions, typing cancel).
    if (update instanceof Api.UpdateNewMessage || update instanceof Api.UpdateNewChannelMessage) {
      const m = update.message;
      if (m instanceof Api.Message) {
        await handleMessage(m);
        if (!m.out && m.peerId instanceof Api.PeerUser) {
          const uid = Number(m.peerId.userId);
          const secs = cancelTyping(uid);
          maybeNewMutual(uid);
          if (reportMessages && m.message) {
            const name = await displayName(uid);
            await report(`✍️ <b>${name}</b>${secs ? ` (${secs} soniya yozib)` : ""} sizga yozdi: ${escape(m.message.slice(0, 300))} · ${escape(stamp())}`);
          }
        }
      }
      return;
    }
    // Short forms (private / basic-group incoming) — capture + typing cancel.
    if (update instanceof Api.UpdateShortMessage && !update.out) {
      const uid = Number(update.userId);
      remember(storeKey(false, null, update.id), { text: update.message || "", fromId: uid, title: null });
      const secs = cancelTyping(uid);
      maybeNewMutual(uid);
      if (reportMessages) {
        const name = await displayName(uid);
        await report(`✍️ <b>${name}</b>${secs ? ` (${secs} soniya yozib)` : ""} sizga yozdi: ${escape((update.message || "").slice(0, 300))} · ${escape(stamp())}`);
      }
      return;
    }
    if (update instanceof Api.UpdateShortChatMessage && !update.out) {
      remember(storeKey(false, null, update.id), { text: update.message || "", fromId: Number(update.fromId), title: null });
      return;
    }

    // Edits.
    if (update instanceof Api.UpdateEditMessage) { await onEdit(update.message, false); return; }
    if (update instanceof Api.UpdateEditChannelMessage) { await onEdit(update.message, true); return; }

    // Deletions.
    if (update instanceof Api.UpdateDeleteMessages) {
      for (const id of update.messages || []) await onDelete(storeKey(false, null, id));
      return;
    }
    if (update instanceof Api.UpdateDeleteChannelMessages) {
      const chan = Number(update.channelId);
      for (const id of update.messages || []) await onDelete(storeKey(true, chan, id));
      return;
    }
  } catch (e) { console.error("[watcher] update error:", e.message); }
});

// ── Story views (polling — Telegram sends no per-view push) ──────────────────
async function pollStories() {
  try {
    const res = await client.invoke(new Api.stories.GetPeerStories({ peer: "me" }));
    const stories = res?.stories?.stories || [];
    for (const story of stories) {
      if (!story?.id) continue;
      const views = await client.invoke(new Api.stories.GetStoryViewsList({
        peer: "me", id: story.id, offset: "", limit: 100, q: "",
        justContacts: false, reactionsFirst: false, forwardsFirst: false,
      })).catch(() => null);
      const list = views?.views || [];
      if (!seenStoryViewers.has(story.id)) {
        // First pass: remember current viewers without spamming old ones.
        seenStoryViewers.set(story.id, new Set(list.map((v) => Number(v.userId))));
        continue;
      }
      const seen = seenStoryViewers.get(story.id);
      for (const v of list) {
        const uid = Number(v.userId);
        if (seen.has(uid)) continue;
        seen.add(uid);
        const name = await displayName(uid);
        const reaction = v.reaction ? " ❤️" : "";
        await report(`👁 <b>${name}</b> storyangizni ko'rdi${reaction} · ${escape(stamp())}`);
      }
    }
  } catch (e) {
    if (debug) console.error("[watcher] story poll:", e.message);
  }
}

// ── Startup ──────────────────────────────────────────────────────────────────
await client.connect();
const me = await client.getMe();
myId = Number(me.id);
myUsernames = [me.username, ...(me.usernames?.map((u) => u.username) || [])].filter(Boolean).map((u) => u.toLowerCase());
try { await client.getDialogs({ limit: 200 }); } catch { /* best effort */ }
// Baseline of current mutual contacts, so we only report NEW ones later.
try {
  const contacts = await client.invoke(new Api.contacts.GetContacts({ hash: 0 }));
  for (const u of contacts?.users || []) if (u.mutualContact) knownMutuals.add(Number(u.id));
} catch { /* best effort */ }

console.log(`[watcher] running as ${me.firstName || ""} (@${me.username || me.id}). Watching typing, mentions, deletes, edits, story views, contacts.`);
await report(`🟢 Nodik watcher ishga tushdi — yozmoqchi bo'lганlar, eslatish, o'chirish/tahrir, story va kontaktларни kuzatyapman · ${escape(stamp())}`);

await pollStories();
setInterval(pollStories, STORY_POLL_MS);

process.on("SIGINT", async () => { await client.disconnect().catch(() => {}); process.exit(0); });
process.on("SIGTERM", async () => { await client.disconnect().catch(() => {}); process.exit(0); });
