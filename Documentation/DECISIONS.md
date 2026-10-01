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

## D8 — Nodogram cannot be deployed to Vercel (or any web host)

**Date:** 2026-10-01 · **Status:** settled, by physics rather than preference

Deploying Nodogram to Vercel was requested and is not possible. Three
independent blockers, any one of which is sufficient:

1. **Platform.** Nodogram is an `arm64` macOS Mach-O binary built on SwiftUI and
   AppKit. Vercel executes Node.js, Python, Go and Ruby on Linux. SwiftUI and
   AppKit do not exist outside Apple platforms, so the entire UI layer has no
   target to run on. This is not a porting task; it is a rewrite.

2. **Statefulness.** Even a rewritten web client could not put *TDLib* on
   Vercel. TDLib requires a long-lived process that continuously calls
   `td_receive`, plus a persistent database directory. Vercel's functions are
   stateless and ephemeral, and their filesystem does not survive between
   invocations. Vercel could host a frontend; it cannot host the Telegram layer.

3. **There is no database to connect.** TDLib owns its own encrypted store, and
   Nodogram's local-only data — drafts, draft history, notes, bookmarks, the
   deletion archive — lives in SQLite on the user's Mac *by design*
   (`SECURITY_MODEL.md` §1, `DATA_MODEL.md`). Moving it to a hosted database
   would invert the privacy model the product is built around: the archive in
   particular can contain messages senders believed were deleted, and putting
   that on a shared server is precisely what the design refuses to do.

**Consequence — the closest correct alternative.** Distribution happens through
GitHub: `.github/workflows/build.yml` builds, tests and packages the app on
every push, and attaches a downloadable `.app` to tagged releases. That gives
"install it from GitHub on any Mac", which is the deployable form this product
actually has.

**If browser or server access is genuinely required**, that is a different
product: a web client, with a Next.js frontend (which *can* live on Vercel) and
a TDLib backend on a stateful host with a persistent volume — Fly.io, Railway,
Render or a VPS. It is a substantial separate project, and it changes the
privacy model, because local-only data would then live on a server. That
trade-off must be decided deliberately, not inherited by accident.
