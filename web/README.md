# Nodogram Web

A Telegram client that runs **entirely in your browser**. No Nodogram server
exists, so message content, drafts and notes never leave your device.

> Independent, unofficial client. Not affiliated with, endorsed by, or
> sponsored by Telegram.

## How it works

| Layer | Choice |
|---|---|
| UI | Next.js 16 (App Router), React 19, Tailwind 4 |
| Protocol | GramJS — MTProto in TypeScript, speaking to Telegram from the browser over WebSocket |
| Storage | IndexedDB via Dexie — chats, messages, drafts, draft history, notes |
| Hosting | Vercel (static; no backend) |

The architecture decision behind this — including why TDLib's WebAssembly build
was evaluated and rejected — is recorded in
[`Documentation/DECISIONS.md`](../Documentation/DECISIONS.md) D8.

## Setup

```bash
cp .env.example .env.local   # then fill in both values
npm install
npm run dev
```

Get your own `api_id` / `api_hash` at
[my.telegram.org](https://my.telegram.org) → *API development tools*.

> **These are public.** In any browser-based Telegram client the credentials
> ship in the JavaScript bundle and can be read by anyone. This is unavoidable
> and is how Telegram's own web client works, but it means your `api_id` could
> be abused by others and flagged. Use an `api_id` you are willing to expose.

## Deploying

Live at **[nodogram.vercel.app](https://nodogram.vercel.app)**.

The Vercel project is connected to this GitHub repository with **Root
Directory = `web`**, so every push to `main` deploys to production and every
pull request gets a preview URL. No manual step is involved.

If you ever recreate the project:

1. Import the repository in Vercel and set **Root Directory** to `web`.
2. Add `NEXT_PUBLIC_TELEGRAM_API_ID` and `NEXT_PUBLIC_TELEGRAM_API_HASH` under
   **Settings → Environment Variables** (Production, Preview, Development).

There is nothing else: no database to provision, no backend to run. Because
the root directory is `web`, CLI deploys must be run from the repository root,
not from inside `web/`.

## Layering

`src/lib/domain` holds the vocabulary and imports nothing. GramJS types stop at
`src/lib/telegram/{client,mapping}.ts`, so a protocol upgrade cannot ripple into
the UI — the same rule the macOS app enforces through its package manifest.

The domain mirrors the macOS app's Swift types deliberately. The two clients are
separate implementations; they must not drift in meaning.

## What works today

Sign-in (phone → code → two-step password) · chat list with real sync ·
conversation view with day separators · sending messages · honest read receipts ·
durable drafts with history in IndexedDB · offline cache · light and dark themes ·
keyboard navigation (⌘K to search, Esc to clear).

## Known limits

- **Read timestamps.** MTProto exposes `readOutboxMaxId` — whether a message was
  read, but not *when*. Nodogram therefore shows "Read · time no longer
  available" rather than inventing a time. The macOS client gets exact times,
  because TDLib exposes `getMessageReadDate`.
- **Protocol layer 198**, versus 229 on the macOS client.
- Media is labelled ("Photo", "Voice message") but not yet rendered.
- No voice or video calls.
