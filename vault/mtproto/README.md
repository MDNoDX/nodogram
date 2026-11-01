# Nodik Watcher — standalone typing monitor

Watches your **own** private chats for what a bot can't see — when someone is
**typing to you but sends nothing**, and (optionally) when someone messages you —
and reports it to your log channel through the bot. It logs in as **your**
Telegram account via a session string, so it needs **no Nodogram** and, on a
server, **no Mac**.

It only ever observes **your own incoming activity** (who writes to you, who is
typing to you) — the same thing Telegram shows you in the app.

## ⚠️ Read first — security

- The **session string** = **full access to your Telegram account**. Treat it
  like your password. Store it only in `.env` (`chmod 600`), never commit or
  share it, and keep the server it runs on secure.
- If it ever leaks, revoke it: Telegram → **Settings → Devices → end that session**.
- Third-party user clients can occasionally be rate-limited or flagged by
  Telegram. This runs as a normal client and only reads your own updates, but
  the risk is yours to accept.

## Setup

**1. Get API credentials.** Go to <https://my.telegram.org> → *API development
tools* → create an app → copy **api_id** and **api_hash**.

**2. Install.**
```bash
cd vault/mtproto
npm install
cp .env.example .env
chmod 600 .env
# edit .env: API_ID, API_HASH, BOT_TOKEN, LOG_CHANNEL
```

**3. Log in (you do this — your code/2FA stay on your machine).**
```bash
node login.mjs
```
Enter your phone, the code Telegram sends, and your 2FA password if you have one.
It prints a **session string** — paste it into `.env` as `MTPROTO_SESSION`.

**4. Run.**
```bash
node watcher.mjs
```
You should see a "🟢 Nodik watcher ishga tushdi" message in your channel.

## Running 24/7, independent of your Mac (a VPS)

Put this folder on any always-on Linux server (a cheap VPS) with Node ≥ 20.
You can run `login.mjs` locally and just copy the session string into the
server's `.env`, so your phone/code never touch the server.

**systemd** (`/etc/systemd/system/nodik-watcher.service`):
```ini
[Unit]
Description=Nodik Watcher
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/nodik-watcher
ExecStart=/usr/bin/node watcher.mjs
Restart=always
RestartSec=5
User=nodik

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl enable --now nodik-watcher
sudo journalctl -u nodik-watcher -f
```

A `pm2 start watcher.mjs --name nodik-watcher` also works if you prefer pm2.

## Options (`.env`)

- `REPORT_MESSAGES=1` — also report every incoming private message (noisier).
  Default `0` = only "tried to type but didn't send".
- `TZ` — timezone for timestamps (default `Asia/Tashkent`).

## Notes

- To also move message/deletion/edit keeping off the Mac, the Node vault
  (`vault/`) + its PostgreSQL can be hosted on the same VPS; only this watcher
  adds the typing signal, which the Business bot API cannot provide.
- Stop any duplicate: if both this watcher and Nodogram run, you may get the
  typing alert twice. Keep one of them as the source for typing.
