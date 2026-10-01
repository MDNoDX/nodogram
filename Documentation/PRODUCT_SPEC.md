# Nodogram — Product Specification

**Phase 1 deliverable.** What Nodogram is, what it does, and what it refuses to
pretend to do.

---

## 1. Positioning

> A fast, private, keyboard-first Mac messenger that speaks Telegram — with the
> message history, drafts, and search that Telegram never gave you.

Nodogram is an **independent, unofficial** Telegram client for macOS. It is not
affiliated with, endorsed by, or sponsored by Telegram Messenger LLP.

It is not a reskin. It keeps Telegram's mature messaging model and adds four
things Telegram structurally does not do:

| | Telegram | Nodogram |
|---|---|---|
| Drafts | One per chat, easily lost | Durable, with version history |
| Deleted messages | Gone from your view too | Optional local archive, opt-in and encrypted |
| Read times | "Read", rarely precise | Exact server-confirmed time, with honest fallbacks |
| Search | Mostly server, no local-only data | Instant local FTS over notes, drafts, archive + operators |

**Who it is for:** people who live in a Mac keyboard, keep long-running
conversations that matter, and are tired of losing a half-written message.

**Design posture:** professional and quiet by default. Fast over flashy.
Animations are subtle, interruptible, and obey Reduce Motion. No feature exists
to be a bullet point — §8 lists what we deliberately left out.

---

## 2. Brand

| | |
|---|---|
| Name | **Nodogram** |
| Tone | Precise, calm, technical. Never cute. |
| Icon | Original mark. **No paper plane. No blue circle.** (See `LEGAL_AND_LICENSES.md` §5.) |
| Accent | Original; deliberately not Telegram's `#2AABEE` / `#229ED9`. Honours the system accent colour when the user prefers it. |
| Type | SF Pro (system). SF Mono for code blocks. |

The icon concept — a layered/stacked glyph suggesting retained history — is
chosen to be visually unrelated to Telegram's mark while reading clearly at
16 pt in the Dock, Finder, Spotlight and notifications.

---

## 3. Layout (brief §4)

```
┌──────────┬────────────────────┬──────────────────────────────┐
│ Sidebar  │  Conversation list │  Active conversation         │
│          │                    │                              │
│ folders  │  rows, incremental │  virtualized message list    │
│ + nav    │  updates only      │  + composer                  │
└──────────┴────────────────────┴──────────────────────────────┘
```

Modes: three-column (default) · compact (list collapsed) · full-width
conversation. Pane widths, window frame, and mode **persist**, per window, and
restore on launch. Multiple windows supported, each with its own state
(brief §41).

---

## 4. Feature inventory

Grouped by the phase that delivers it (`ARCHITECTURE.md` §11). Everything here
is implementable on TDLib 1.8.67 unless flagged in §8.

### 4.1 Chats and messages

- Chat list rows: avatar, name, verification badge, last-message preview, group
  sender name, timestamp, unread badge/count, muted, pinned, **draft**,
  attachment, mention and reaction indicators, outgoing status.
- Incremental row updates only. No full-list reload on an event (brief §6).
- Message types: text, rich text, emoji, custom emoji, stickers, GIFs, photos,
  video, documents, audio, voice, contacts, locations, polls, links, code
  blocks, quotes, replies, forwards, reactions, albums/media groups, pinned,
  scheduled, silent.
- Grouping by sender/time; date separators (`TODAY`, `YESTERDAY`, `SEPTEMBER 29`).
- Virtualized list: a 100,000-message chat stays usable and scrolls at 60 FPS.
- **Position restoration** (brief §60): reopening a chat returns to the last
  visible message, scroll offset, and unread boundary. It does **not** jump to
  the newest message if the user was reading older content.

### 4.2 Message status (brief §8)

`sending → sent → delivered → read`, plus `failed` and `retrying`.
Server-confirmed state is stored and rendered **separately** from local
optimistic state. We never fake a delivery or read state.

### 4.3 Read times (brief §9, §66)

Exact, server-confirmed read time where Telegram provides it — "Read at 14:32".
All five protocol outcomes get honest copy; see `ARCHITECTURE.md` §6.2 for the
full mapping. Group chats show a true "Read by" list with per-viewer times,
within Telegram's limits. Hovering any timestamp reveals the precise value.

### 4.4 Drafts (brief §10, §11, §23) — differentiator

Autosaved continuously (debounced), and force-flushed on chat switch, window
close, app quit, and system sleep. A draft survives app restart, Mac restart,
crash, and network loss.

Preserved per draft: text, entities, attachments, reply target, forward context,
cursor position, selection range, timestamp, chat id.

**Draft History:** previous versions retained locally, with restore, compare,
delete, disable, and a retention period. Local and private by default — never
uploaded. (The text itself still syncs to your other Telegram devices via
TDLib's own draft, because that is expected behaviour; the *history* does not.)

UI: a quiet "Draft saved" indicator. Never an interruption while typing.

### 4.5 Local archive (brief §12, §13, §67) — differentiator

Opt-in retention of messages deleted remotely, with per-scope control and
retention limits. Every deletion produces an event record (ids, sender,
original and deletion timestamps, type) even when content is not retained.

A dedicated **Local Archive** page keeps this discoverable without polluting
normal chats, filtered by: deleted remotely · edited remotely · bookmarked ·
with notes · draft history.

Encrypted, erasable, off by default, and explained in plain language.
See `SECURITY_MODEL.md` §6 — this is the app's highest-risk feature and is
treated as such.

### 4.6 Bookmarks, collections, notes (brief §16, §17)

Star/bookmark any message; tag it; file it into collections (Study, Work,
Important, Ideas, To Do, Personal, custom) with custom colours and icons.

**Local notes**: a private annotation attached to a message. Never transmitted.

### 4.7 Search (brief §18, §19)

Operators: `from: in: before: after: during: has: type: tag: is:`
e.g. `from:Ali in:Backend after:2026-09-01 type:file`

Searches message text, sender, chat, dates, media type, filename, links,
bookmarks, **archive, draft history, and notes** — the last three being data no
other client has. Local results are instant and work offline.

**⌘K** opens a universal palette over chats, contacts, messages, files,
settings, commands and actions — including executing actions ("mute current
chat" → ↵).

### 4.8 Keyboard (brief §21)

Every meaningful action has a shortcut; all are customizable; none shadow a
standard macOS binding.

| | | | |
|---|---|---|---|
| ⌘K global search | ⌘F in-chat search | ⌘N new message | ⌘⇧N new group |
| ⌘⇧P palette | ⌘↵ send | ⎋ cancel/close | ↑ ↓ navigate list |
| ⌘⇧A archive | ⌘⇧M mute | ⌘⇧U mark unread | ⌘1–9 folders |

### 4.9 Composer (brief §22, §47)

Multiline, emoji picker, attachments, drag-and-drop, paste image/file, voice
messages, formatting, reply/edit/forward previews, draft indicator, scheduled
and silent send.

A formal state machine — `EMPTY · TYPING · REPLYING · EDITING · FORWARDING ·
ATTACHING · SENDING · FAILED · DRAFT_SAVED · OFFLINE_PENDING` — with
deterministic transitions, so UI state and database state cannot diverge.
Typing never lags.

### 4.10 Media and files (brief §24, §25)

Viewer: full screen, zoom, rotate, next/previous, keyboard navigation,
metadata, save, copy, share, reveal in Finder, Quick Look, download progress,
streaming. Video: speed, frame seeking, PiP. Files: resumable downloads,
pause/retry, content-hash dedupe, no needless re-download.

### 4.11 Notifications (brief §29, §30, §59)

Native, with reply/mark-read/mute actions. **Grouped** — 20 messages from one
chat is "Ali · 12 new messages", not 20 banners — and opening one lands on the
correct unread position. Privacy mode shows "You have a new message" only.
Focus modes (Work, Study, Sleep, Personal) each control notifications, sound,
badges, previews, and per-chat rules.

### 4.12 Organization, offline, settings

Pin · archive · mute · folders · favourites · unread-only · mentions; sorting by
recent / unread-first / alphabetical / manual / pinned-first.

**Offline** (brief §27): read cached messages, search locally, browse cached
media, compose, draft, bookmark, annotate, organize. Explicit sync states;
user-created content is never silently lost. Connection state is shown
unobtrusively (Connected · Connecting · Offline · Syncing) — no nagging banners.

Settings sections: General · Appearance · Chats · Messages · Notifications ·
Privacy · Security · Storage · Drafts · Archive · Search · Keyboard · Folders ·
Accounts · Advanced · About. Plus a **Privacy Center** enumerating every
category of local data with per-category control (brief §36).

Multi-account with full isolation of sessions, caches, drafts, archives,
settings, search indexes and keys (brief §40).

Export to JSON · HTML · Markdown · plain text, **always labelling** which data
is remote, local-only, draft history, or archive (brief §37).

### 4.13 Accessibility and localization (brief §54, §55)

VoiceOver throughout, full keyboard navigation, visible focus states, Dynamic
Type, high contrast, Reduce Motion, Reduce Transparency. **State is never
communicated by colour alone.**

Localized from day one — no hard-coded user-facing strings, keys like
`chat.mark_as_read`, `draft.saved`, `message.read_at`. Launch languages:
**English, Uzbek (Latin), Uzbek (Cyrillic), Russian.**

---

## 5. Performance targets (brief §52)

| Metric | Target |
|---|---|
| Cold launch to usable chat list | < 1.0 s on M1 |
| Open cached conversation | < 100 ms |
| Scrolling | 60 FPS sustained, incl. 100k-message chats |
| Keystroke latency | imperceptible; no main-thread work per keystroke |
| Local search (indexed) | < 50 ms to first results |
| Memory | bounded; never load a full chat into RAM |

Verified by a developer-only diagnostics panel (brief §85), hidden from normal
users, measuring FPS, memory, CPU, DB latency, render time, search latency,
network latency, cache hit rate, transfer speeds and sync queue depth.

---

## 6. Error handling and empty states (brief §71, §72)

No stack traces in normal UI. Messages state what happened and what happens
next, with a **Details** affordance for advanced users:

- "Couldn't send message. We'll retry automatically."
- "File upload paused because you're offline."
- "Your draft was recovered after an unexpected shutdown."

Empty states are useful, not decorative — each explains what belongs there and
offers the action that fills it.

---

## 7. Every async operation

has `loading · success · failure · retry · cancel` where applicable.
Every persistent entity has defined `creation · update · deletion · migration ·
recovery` behaviour. Schema upgrades never destroy user data.

---

## 8. What Nodogram does not do

Stated up front, because a spec that only lists wins is not a spec.

| Not included | Why |
|---|---|
| **Voice and video calls (v1)** | TDLib provides signalling only; real calls need the `tgcalls`/WebRTC media stack. Shipping a fake call button would violate the brief's own quality rule. The palette entry offers to open the official app instead. See `ARCHITECTURE.md` §10.1. |
| Recovering messages never received | Physically impossible. The archive retains only what this Mac actually got. |
| Defeating server-side deletion | The archive is local retention, not server access. Stated in-app. |
| Message-body Spotlight indexing by default | Would copy plaintext into a system index outside our encryption. Opt-in only. |
| Faked read receipts or delivery states | Brief §8/§45. Telegram's reciprocity rule is explained, not worked around. |
| Telemetry | None by default. No content, drafts, notes or archives ever collected. |
| Touch Bar as a core dependency | Deliberately optional; the keyboard model is the product. |
| Secret chats (v1) | TDLib supports them, but they are device-bound and interact badly with archive/draft-history semantics. Deferred until those interactions are designed honestly rather than bolted on. |

---

## 9. Success criteria

Nodogram v1 succeeds if:

1. A Telegram power user can switch to it for daily use without missing core
   messaging (calls excepted and clearly disclosed).
2. A half-written message is never lost, under any shutdown path.
3. Local search returns useful results in under 50 ms, offline.
4. A 100,000-message conversation scrolls smoothly.
5. Read-time and archive features are understood correctly by users — because
   the copy is honest — and never overclaim.
6. It feels like a Mac app built by a desktop software team, not a web page in a
   window, and not a generated clone.

---

*Companion documents: `ARCHITECTURE.md`, `SECURITY_MODEL.md`,
`LEGAL_AND_LICENSES.md`, `UPSTREAM.md`.*
