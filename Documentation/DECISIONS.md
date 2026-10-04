# Decision Record

Decisions that are settled, so they are not relitigated. Each entry records the
choice, the date, and the consequence that follows from it.

---

## D1 — Build on TDLib, do not fork Telegram's clients

**Date:** 2026-10-01 · **Status:** settled

Forking `overtake/TelegramSwift` (GPL-2.0-or-later) would force Nodogram's
license and block Mac App Store distribution. TDLib (BSL-1.0) with MIT wrappers
leaves both free.

**Consequence:** we write our own UI and application layers; we inherit no
Telegram UI, and no voice/video call stack (see D4). GPL repositories are
reference only — no code is taken. Full reasoning in
`LEGAL_AND_LICENSES.md` §1.

---

## D2 — Minimum deployment target: macOS 15 (Sequoia)

**Date:** 2026-10-01 · **Status:** settled · **Revised** from macOS 14 the same
day, on evidence.

**The correction.** macOS 14 was chosen first, for reach. Linking then emitted
hundreds of warnings of the form *"object file ... was built for newer 'macOS'
version (15.0) than being linked (14.0)"*. Inspecting the binary explains why:

```
$ otool -l -arch arm64 TDLibFramework | grep minos | sort | uniq -c
 954  minos 11.0
 553  minos 15.0
```

**553 of 1507 arm64 objects in the prebuilt TDLib binary are compiled against a
macOS 15 floor** — roughly a third of the library. TDLibKit's manifest advertises
`macOS 10.15`, but the shipped binary does not honour that.

Declaring macOS 14 would therefore have shipped an app that *installs* on
Sonoma and may fail at launch or on first use of an affected code path. That
could not be verified here either, since development is on macOS 26.5. An
unverifiable support claim is worse than a narrower honest one.

**Consequence:** minimum is **macOS 15.0**, set in `Package.swift`,
`Tools/tdlib-probe/Package.swift`, and `LSMinimumSystemVersion`. The link
warnings are gone, which is the confirmation that the floor now matches reality.
Reach is narrower than hoped; the alternative was a claim we could not stand
behind.

Any API newer than macOS 15 must still be guarded with `if #available(…)` and
have a working fallback.

---

## D3 — Nodogram's own license: deferred

**Date:** 2026-10-01 · **Status:** open, deliberately

No `LICENSE` file is present, so no license is implied by accident. Under
default copyright this means all rights reserved; nothing is lost by waiting.

**Consequence:** does not block any phase. Must be settled before any public
distribution — it is on the release checklist in `LEGAL_AND_LICENSES.md` §7.
Options and their trade-offs: `LEGAL_AND_LICENSES.md` §6.

---

## D4 — No voice or video calls in v1

**Date:** 2026-10-01 · **Status:** settled for v1

TDLib performs call **signalling** only: `callStateReady` hands over call
servers and an encryption key, and expects the client to carry the media. That
media layer is `tgcalls` + `tg_owt` (a full WebRTC fork) — a very large native
dependency and a significant audit surface.

**Consequence:** the command palette's call entry offers to open the official
app rather than presenting a button that cannot work. This is disclosed in
`README.md` and `PRODUCT_SPEC.md` §8 rather than left for users to discover.
Revisit as a dedicated phase after v1.

---

## D5 — Message list and composer text view are AppKit

**Date:** 2026-10-01 · **Status:** settled, to be validated by measurement

A 100,000-message conversation at 60 FPS is the hardest constraint in the
product brief. SwiftUI's `List` does not give sufficient control over cell reuse
and heterogeneous variable-height content at that scale.

**Consequence:** `NSTableView`/`NSTextView` behind `NSViewRepresentable` for
those two surfaces only; SwiftUI everywhere else. This is an assumption, so
**Phase 6 benchmarks it** rather than trusting it. If SwiftUI meets the target,
this decision is reversed and recorded here.

---

## D6 — One TDLib manager per process, one client per account

**Date:** 2026-10-01 · **Status:** settled, enforced by tests

Creating a second `TDLibClientManager` aborts the process (SIGABRT), because
each one starts its own `td_receive` loop and TDLib forbids concurrent receive.

**Consequence:** `TelegramGateway` shares a single process-wide manager and owns
one client per account — which is exactly the structure multi-account isolation
needs. `shutdown()` closes only its own client, never `closeClients()`, whose
busy-wait would stall other accounts. Covered by
`Tests/Integration/TelegramGatewayTests.swift`.

---

## D7 — The app ships as a hand-assembled bundle, not an .xcodeproj

**Date:** 2026-10-01 · **Status:** settled

`Tools/build-app.sh` compiles the SPM executable and assembles
`build/Nodogram.app`, injecting Telegram credentials into `Info.plist` from the
git-ignored `Config/Secrets.xcconfig` at build time.

**Consequence:** one build path that works identically from the CLI and from CI,
with no generated project to drift out of sync. Credentials stay out of source.
Signing is ad-hoc unless `DEVELOPMENT_TEAM` is set, which is enough to run
locally and keeps Keychain access working. A notarized build for distribution
needs a real Developer ID, which is a packaging-phase concern.

---

## D8 — The macOS app cannot go on Vercel; a web client can

**Date:** 2026-10-01 · **Status:** settled · **Corrected** the same day

**What was right.** The *macOS app* cannot be deployed to Vercel. It is an
`arm64` Mach-O binary built on SwiftUI and AppKit; Vercel runs Node.js on Linux,
where those frameworks do not exist. That part stands.

**What was wrong.** The original decision generalised that into "Nodogram cannot
be deployed to any web host", and claimed the Telegram layer always needs a
long-lived stateful process. That is false for a browser client:

- **TDLib officially compiles to WebAssembly** (`tdweb`, in TDLib's own
  repository), running entirely in the browser with persistent storage.
- **GramJS** (`telegram` on npm) implements MTProto in pure TypeScript and runs
  in the browser.

Either removes the need for a backend entirely, which makes a Vercel-only
deployment genuinely possible. Telegram's own web clients work this way.

**Chosen foundation: GramJS.** Measured against the alternatives:

| Option | Vercel-only | Protocol currency | Verdict |
|---|---|---|---|
| Official `tdweb` | yes | **1.8.0, published 2021-12-30** — ~5 years stale | rejected |
| `@dibgram/tdweb` | yes | 1.8.40 (2024-11-21), unofficial prebuild | rejected |
| **GramJS (`telegram`)** | **yes** | **2.26.22 (2025-02-12), actively maintained** | **chosen** |
| Next.js + TDLib backend | no — needs a second stateful host | 1.8.67 | rejected |

The tdweb builds are stale and unofficial, and depend on one maintainer running
Emscripten 3.1.1 by hand. GramJS is current, widely used, and ships its own
browser build.

**Consequence.** The web client is a *separate product* in `web/`, sharing the
domain vocabulary and visual identity of the macOS app but not its code — Swift
and TypeScript cannot share an implementation. It gives up TDLib's built-in
local database and ordered-update guarantees, which we therefore implement
ourselves over IndexedDB.

**Privacy is preserved**, and this is why a browser client is acceptable at all:
local-only data (drafts, draft history, notes, bookmarks, the deletion archive)
lives in the user's own browser via IndexedDB, not on a server. No Nodogram
server ever sees message content. `SECURITY_MODEL.md` §1 still holds.

**One honest cost.** In any browser-based Telegram client the `api_id` and
`api_hash` are shipped in the JavaScript bundle and are therefore public. This
is unavoidable and is how Telegram's own web clients operate, but it means the
credentials identify the app publicly and could be abused by others, which risks
the `api_id` being flagged. Recorded so the trade-off is deliberate.

---

## D9 — Messages deleted by others stay in place, marked deleted

**Date:** 2026-10-01 · **Status:** amended 2026-10-04 — now off by default (see D13)

Every message the Mac receives is recorded in `MessageArchive`
(Nodogram/Core/Archive). When Telegram reports a permanent deletion, the
record is marked rather than dropped, and the conversation keeps the message
where it was — dimmed, dash-bordered, with "Deleted · 18:42".

**Honest limits, also shown in Settings → Privacy:** it cannot recover a
message this Mac never received (sent and deleted while Nodogram was closed),
and it does not undo the deletion on Telegram. TDLib cache evictions
(`from_cache`) are never treated as deletions.

**Protection:** content is AES-GCM encrypted under a Keychain key; only ids and
dates are plaintext. Tests assert the text never appears in the database file
and that a different key reads nothing. Ordinary records expire after 90 days;
deleted ones per the user's retention choice (7 d / 30 d / 1 y / forever, the
last behind a confirmation). "Erase Archive" removes everything and vacuums.

---

## D10 — Chats that forbid saving are honoured

**Date:** 2026-10-01 · **Status:** settled

When Telegram marks a message `can_be_saved = false` (the chat owner turned on
"Restrict saving content"), Nodogram shows the media but offers no Save, Show in
Finder, Copy or open-in-another-app. This is the owner's decision, Telegram's
API terms require clients to respect it, and bypassing it would risk the
user's `api_id` being banned. Every other chat has the full set of actions.

---

## D11 — Media playback architecture

**Date:** 2026-10-01 · **Status:** settled, verified by tests

- **Video streams** through `StreamingAssetLoader`: AVPlayer's byte-range
  requests are answered by TDLib `downloadFile(offset, limit)` +
  `readFilePart`, so seeking anywhere, ±10 s, and resuming mid-video start
  without downloading what came before. TDLib returns early from a synchronous
  download when another range is requested, so availability is re-checked with
  `getFileDownloadedPrefixSize` rather than trusted. Tested with a generated
  H.264 file and a source that refuses unprepared bytes.
- **Voice messages** (OGG Opus) are demuxed in Swift and decoded by macOS's own
  Opus decoder — no bundled codec. Round-trip tested with Apple's encoder.
- **Resume positions** are keyed by Telegram's remote unique id, which is stable
  across sessions (the numeric file id is not).
- **Saving** copies into a user-chosen folder (default ~/Downloads/Nodogram);
  TDLib's internal cache is never shown as the place to find files.

---

## D12 — Development builds get a stable code identity

**Date:** 2026-10-01 · **Status:** settled until a Team ID is configured

An ad-hoc signature's identity is the binary's hash, so every rebuild looked
like a new app to the Keychain and macOS asked for the login password again.
`Tools/build-app.sh` now pins the designated requirement to the bundle
identifier. This is weaker than a certificate (another ad-hoc app could claim
the identifier); setting `DEVELOPMENT_TEAM` replaces it with a real one.

---

## D13 — Telegram API Terms compliance

**Date:** 2026-10-04 · **Status:** settled

The audit found three conflicts with Telegram's API Terms of Service, which
put the user's api_id at risk:

- **Deleted-message archive (ToS 1.4).** Clients must not interfere with
  self-destructing content. The archive is now **off by default**; it never
  records self-destructing, auto-deleting or secret-chat messages
  (`Message.isEphemeral`), nor messages in chats that forbid saving. A
  one-time erase (`archive.complianceErase.v1`) removed anything recorded
  under the old default.
- **Sponsored messages (ToS 3.3).** Channels show Telegram's sponsored
  messages at the end of the history, report views only once the full text is
  visible, and report clicks — as the official apps do.
- **Local data at rest.** The TDLib database is now encrypted with a key kept
  in the Keychain (`app.nodogram.tdlib`); existing databases are migrated.

Related hardening from the same audit: downloaded files get the
`com.apple.quarantine` attribute and executables ask before opening; links
open directly only for http(s), mailto, tel and tg — anything else asks.

---

## D14 — Staying on the newest TDLib automatically

**Date:** 2026-10-04 · **Status:** settled

`.github/workflows/update-tdlib.yml` runs daily. When Swiftgram publishes a
newer TDLibKit build (ordered by publish date — tags share a version and differ
only by hash), it moves the exact pin, builds, runs every test against the new
binary, and opens a pull request that auto-merges if the repository allows
it. Nothing reaches `main` untested. New TDLib versions sometimes rename API
fields; when that breaks the build, the workflow fails visibly instead of
opening a PR.


---

## D15 — Keeping what Telegram shows only briefly

**Date:** 2026-10-04 · **Status:** settled, at the user's explicit request

The user asked, after being told of the API Terms risk (D13), for deleted
messages to be kept and clearly visible. They are now kept **by default**
(Settings → Nodogram Features turns it off), shown in place with a red
"Deleted … · kept on this Mac" banner, listed under **Deleted**, and announced
by a quiet notification. Every edit is kept too, as a version history opened
from the "edited" label. The line Nodogram does not cross is ToS 1.4's explicit
one: self-destructing, auto-deleting, secret-chat and copy-protected messages
are never recorded.

Also kept locally, all from data Telegram already delivers to this client:

- **Typing log** — who started typing, when, for how long, and whether a
  message followed ("typed but didn't send"), with optional notifications.
- **Story viewers** — polled once a minute while the app runs and kept after
  Telegram's own list expires.
- **Keyword alerts** — notify on chosen words even in muted chats.

**Not built: "ghost mode."** Hiding online status, read receipts or typing is
named verbatim in ToS 1.4 as forbidden ("tampering with the 'read' statuses of
messages (e.g. implementing a 'ghost mode')"). Clients that ship it risk the
user's api_id and account; Nodogram does not.
