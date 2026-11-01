// Nodik Watcher — a standalone MTProto user-session monitor.
//
// Runs as YOUR Telegram account (via the session string from login.mjs) and
// watches your private chats for things a bot cannot see:
//   • someone is TYPING to you, then sends nothing ("tried to write")
//   • someone sends you a message (optional, REPORT_MESSAGES=1)
// It reports each to your log channel through the bot, so it shows up with the
// rest of Nodik's alerts. It needs no Nodogram and, on a server, no Mac.
//
// It only ever sees YOUR OWN incoming activity — who writes to you and who is
// typing to you — which Telegram already shows you in the app. It does not
// touch anyone else's private data.

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

if (!apiId || !apiHash || !session) {
  console.error("Missing API_ID / API_HASH / MTPROTO_SESSION in .env — run `node login.mjs` first.");
  process.exit(1);
}
if (!botToken || !channel) console.warn("[watcher] BOT_TOKEN / LOG_CHANNEL not set — events will only be logged to the console.");

const TYPING_SETTLE_MS = 8000;   // how long after the last typing to call it "didn't send"
const NAME_TTL_MS = 10 * 60 * 1000;

const escape = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const nameCache = new Map();     // userId -> { name, at }
const typingState = new Map();   // userId -> { timer, lastAt }

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
  if (hit && Date.now() - hit.at < NAME_TTL_MS) return hit.name;
  let name = "Kimdir";
  try {
    const entity = await client.getEntity(userId);
    name = [entity.firstName, entity.lastName].filter(Boolean).join(" ")
      || (entity.username ? "@" + entity.username : null) || `id ${userId}`;
  } catch { /* unknown / inaccessible */ }
  nameCache.set(key, { name, at: Date.now() });
  return name;
}

function stamp() {
  return new Date().toLocaleString("en-GB", { hour12: false, timeZone: env.TZ || "Asia/Tashkent" });
}

// Someone typed to you in a private chat. Debounce: if no message arrives
// within the settle window, it counts as "tried to write but sent nothing".
async function onTyping(userId) {
  const key = String(userId);
  const prev = typingState.get(key);
  if (prev?.timer) clearTimeout(prev.timer);
  const timer = setTimeout(async () => {
    typingState.delete(key);
    const name = await displayName(userId);
    await report(`👀 <b>${escape(name)}</b> sizga yozmoqchi bo'ldi, lekin yubormadi · ${escape(stamp())}`);
  }, TYPING_SETTLE_MS);
  typingState.set(key, { timer, lastAt: Date.now() });
}

// A real message arrived from that user → they sent it; cancel the "tried" timer.
function cancelTyping(userId) {
  const key = String(userId);
  const prev = typingState.get(key);
  if (prev?.timer) { clearTimeout(prev.timer); typingState.delete(key); }
}

client.addEventHandler(async (update) => {
  try {
    // Private-chat typing (not groups).
    if (update instanceof Api.UpdateUserTyping) {
      if (update.action instanceof Api.SendMessageTypingAction) await onTyping(update.userId);
      return;
    }
    // Incoming private message.
    if (update instanceof Api.UpdateShortMessage && !update.out) {
      cancelTyping(update.userId);
      if (reportMessages) {
        const name = await displayName(update.userId);
        await report(`✍️ <b>${escape(name)}</b> sizga yozdi: ${escape((update.message || "").slice(0, 300))} · ${escape(stamp())}`);
      }
      return;
    }
    if (update instanceof Api.UpdateNewMessage) {
      const m = update.message;
      if (m && !m.out && m.peerId instanceof Api.PeerUser) {
        const uid = m.peerId.userId;
        cancelTyping(uid);
        if (reportMessages && m.message) {
          const name = await displayName(uid);
          await report(`✍️ <b>${escape(name)}</b> sizga yozdi: ${escape(m.message.slice(0, 300))} · ${escape(stamp())}`);
        }
      }
      return;
    }
  } catch (e) { console.error("[watcher] update error:", e.message); }
});

await client.connect();
const me = await client.getMe();
console.log(`[watcher] running as ${me.firstName || ""} (@${me.username || me.id}). Watching private-chat typing${reportMessages ? " and messages" : ""}.`);
await report(`🟢 Nodik watcher ishga tushdi — yozmoqchi bo'lганларни kuzatyapman · ${escape(stamp())}`);

// Keep the process alive.
process.on("SIGINT", async () => { await client.disconnect().catch(() => {}); process.exit(0); });
process.on("SIGTERM", async () => { await client.disconnect().catch(() => {}); process.exit(0); });
