# Nodogram Vault

Keeps the messages people send you in private chats, through **your own
Telegram Business bot**, and tells you at once — with the original text,
photos, voice and files — when someone deletes or edits one.

Why a bot, not the app alone: a Business bot receives every message of your
private chats as an official Telegram feature, and Telegram holds its updates
for 24 hours. So the Vault catches messages sent and deleted while your Mac
was asleep, as long as it comes back within a day. The Nodogram app merges
what the Vault kept into each chat and the **Deleted** section.

It serves one account only: connections from any other account are ignored
and the bot answers no one but you.

## What it does not do

Typing and online status never reach bots; the Nodogram app logs typing while
it runs (it keeps running in the menu bar). Self-destructing and
copy-protected media is never copied.

## Setup (once)

1. `~/Library/Application Support/Nodogram/vault.env` (owner-only, 0600):

   ```
   BOT_TOKEN=…            # from @BotFather; never commit it
   OWNER_ID=…             # your Telegram user id
   DATABASE_URL=postgresql://<you>@127.0.0.1:5432/nodogram_vault
   VAULT_PORT=47823
   VAULT_API_TOKEN=…      # random; the Nodogram app reads it from here
   ```

2. `createdb -h 127.0.0.1 nodogram_vault`, then `vault/scripts/install.sh`
   (a LaunchAgent: starts at login, restarts if it stops).
3. In **@BotFather** → /mybots → your bot → Bot Settings → **Secretary Mode** → Enable
   (formerly “Business Mode”; in BotFather's Open panel: bot → Settings → Mode Settings).
4. Open the bot and press **Start** (bots cannot message you first).
5. Telegram → Settings → **Account** → **Chat automation** (older apps:
   Telegram Business → Chatbots) → add the bot for all 1-to-1 chats. No
   Premium is needed, and the bot needs no permission to reply.

Bot commands: `/status`, `/deleted [n]`, `/search words`.

Logs: `~/Library/Logs/Nodogram/vault.log` · Remove: `vault/scripts/uninstall.sh`
· Tests: `npm test`.
