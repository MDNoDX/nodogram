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

## D2 — Minimum deployment target: macOS 14 (Sonoma)

**Date:** 2026-10-01 · **Status:** settled

**Consequence:** `@Observable`, SwiftUI's modern navigation, and Swift 6 strict
concurrency are all available, while Macs from 2023 and earlier remain
supported. Any API newer than macOS 14 must be guarded with
`if #available(…)` and have a working fallback — not a degraded dead end.

Development and verification happen on macOS 26.5, so **Phase 2 must add a
macOS 14 CI job**; building only on 26.5 would let a newer-API dependency slip
in unnoticed.

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
