# Legal and Licenses

**Project:** Nodogram — an unofficial, independent macOS client for Telegram
**Status:** Phase 1 (analysis). No third-party source has been vendored into this
repository yet. This document is the decision record that governs what may be.

---

## 1. Executive summary — the decision that shapes the project

There are two viable foundations for a third-party Telegram client on macOS, and
they carry **incompatible licensing consequences**. This was the first thing
investigated, because it cannot be revisited cheaply later.

| Path | Foundation | License result | Mac App Store | Our freedom |
|---|---|---|---|---|
| **A — chosen** | TDLib (BSL-1.0) + TDLibKit (MIT) | We choose our own | Possible | Full |
| B — rejected | Fork `overtake/TelegramSwift` | **GPL-2.0-or-later, mandatory** | **Blocked** | Derivative work |

**Decision: Path A.** We build on TDLib and write our own application and UI
layer. We do **not** fork or copy from the GPL-licensed Telegram clients.

### Why Path B was rejected

Forking `overtake/TelegramSwift` (the official Telegram macOS client) would make
Nodogram a derivative work of GPL-2.0-or-later code. Consequences:

1. **Nodogram would be forced to be GPL-2.0-or-later.** We could not choose our
   own license. Telegram's own fork rules state this plainly: *"**Do** publish
   your code. The GPL license requires it!"*
2. **Mac App Store distribution would be blocked.** The FSF holds that GPLv2
   §6 ("you may not impose any further restrictions") conflicts with the App
   Store's DRM and per-account distribution terms. This is the precedent that
   removed VLC from the App Store in January 2011. GPLv3 (Telegram Desktop)
   is worse for this purpose, not better, because of its explicit anti-DRM and
   anti-tivoization terms.
3. **The build is extremely heavy and partly inaccessible.** Its submodules are
   declared with SSH URLs (`git@github.com:…`), so a clean clone requires
   configured SSH keys, and it pulls `tg_owt` — a full WebRTC fork — plus
   `tgcalls`, `rlottie`, `libtgvoip`, Boost.Regex and a Bazel-based
   `Telegram-iOS` fork. Build times are measured in hours.
4. **It fights our product goals.** It is Swift 5.0-era code built on a bespoke
   AppKit layer (`TGUIKit`) and the `Postbox`/`SwiftSignalKit` stack. Our brief
   demands Swift 6 strict concurrency, a native-feeling macOS UI, and a
   keyboard-first interaction model. Inheriting another client's UI framework
   would make those harder, not easier.

Path B is only correct if the goal is to ship a *patched Telegram*. Our goal is a
different product that speaks Telegram's protocol. Path A serves that.

> **Consequence to accept honestly:** Path A means we do not inherit Telegram's
> UI, nor its voice/video call media stack. See §5 and `ARCHITECTURE.md` §Limitations.

---

## 2. Component inventory

Every component we intend to depend on. Versions are those verified on
2026-10-01 by inspecting the upstream sources directly.

### 2.1 Accepted dependencies

| Component | Repository | Version / commit | License | Role | Modified? |
|---|---|---|---|---|---|
| **TDLib** | `github.com/tdlib/td` | `1.8.67` (from `CMakeLists.txt` on `master`) | **Boost Software License 1.0** | Telegram protocol, MTProto, encryption, local message store, ordered updates | No — consumed as prebuilt binary |
| **TDLibFramework** | `github.com/Swiftgram/TDLibFramework` | `1.8.67-0efabf93` | **MIT** | Prebuilt `.xcframework` of TDLib for Apple platforms; links `libc++`, `libz` | No |
| **TDLibKit** | `github.com/Swiftgram/TDLibKit` | `1.5.2-tdlib-1.8.67-0efabf93` | **MIT** | Generated Swift bindings over TDLib, async/await | No |

**Boost Software License 1.0 (TDLib)** is permissive and notably does **not**
require attribution for binary-only redistribution. We will attribute anyway —
see §4.

**MIT (TDLibKit, TDLibFramework)** requires the copyright notice and permission
notice be preserved in distributions. We satisfy this via the in-app
acknowledgements screen and `Documentation/THIRD_PARTY_NOTICES.md` (§4).

### 2.2 Studied for reference, deliberately NOT used as source

We read these to understand proven interaction and synchronization patterns. We
take **ideas and protocol understanding** from them, not code. No file, function,
or verbatim structure is copied.

| Component | Repository | License | Why not used |
|---|---|---|---|
| Telegram for macOS | `github.com/overtake/TelegramSwift` | GPL-2.0-or-later | Copyleft would force our license and block App Store (§1) |
| Telegram Desktop | `github.com/telegramdesktop/tdesktop` | GPL-3.0 **with OpenSSL exception** | Same, plus C++/Qt — wrong stack for a native Mac app |
| `tgcalls` / `tg_owt` | `github.com/desktop-app/tg_owt` | `tg_owt`: BSD-3-Clause AND BSD-2-Clause AND Apache-2.0 AND MIT | Only needed for call *media*; see §5 |

> **A boundary we hold deliberately.** "Studied for reference" is a real legal
> line, not a euphemism. Reading GPL code and then writing our own
> implementation of the same *idea* is permitted; copying its expression is not.
> In practice: no copy-paste from these repositories, ever, including
> "just this one helper". Where we knowingly implement a pattern these clients
> also use, the commit message says so.

### 2.3 Telegram server

Telegram's server-side code is **not open source** and is not available to us.
We make no attempt to reimplement, emulate, or reverse-engineer it. Nodogram is
a client that talks to Telegram's production servers through the official API.

---

## 3. Telegram API terms

Verified against `core.telegram.org/api/obtaining_api_id`.

1. **We must obtain our own `api_id` / `api_hash`.** Telegram's fork rules:
   *"**Do** get your own API ID."* One `api_id` per phone number.
2. **Credentials must never be committed.** Telegram warns that using their
   sample credentials in a released app triggers `API_ID_PUBLISHED_FLOOD`
   errors *for our users*. Handling: `Config/Secrets.xcconfig` (git-ignored),
   with `Config/Secrets.example.xcconfig` committed as the template. See
   `README.md` for exactly where to paste them.
3. **No flooding, spamming, or faking engagement.** Violations are met with
   permanent account bans. Nodogram sends no unsolicited traffic; it has no
   bulk-messaging or automation feature, and typing indicators are rate-limited
   and auto-expiring (`PRODUCT_SPEC.md` §Typing).
4. Accounts using unofficial clients may be placed under observation by
   Telegram. This is disclosed to the user in onboarding — we do not hide that
   this is an unofficial client.

---

## 4. Attribution and notices

Obligations we will discharge before any distribution:

- `Documentation/THIRD_PARTY_NOTICES.md` — full verbatim license text of
  TDLib (BSL-1.0), TDLibKit (MIT), TDLibFramework (MIT).
- **In-app:** Settings → About → Acknowledgements, rendering the same notices.
  This is the user-visible discharge of the MIT notice requirement.
- **Source availability:** Not legally required under BSL-1.0/MIT. Our own
  license choice is still open (§6).
- A clear statement, in-app and in `README.md`:
  > Nodogram is an independent, unofficial client. It is not affiliated with,
  > endorsed by, or sponsored by Telegram Messenger LLP.

---

## 5. Trademark and branding

Telegram's fork rules state: *"**Don't** call your fork **Telegram** — or at
least make sure your users understand that yours is unofficial"* and *"**Don't**
use our standard logo (white paper plane in a blue circle) for your fork."*

Our compliance:

| Requirement | Compliance |
|---|---|
| Name | **Nodogram** — original. No use of "Telegram", "TG", or lookalikes. |
| Logo / icon | Original mark. **No paper plane. No blue circle.** See `PRODUCT_SPEC.md` §Brand. |
| Colour | Original accent, deliberately not Telegram's `#2AABEE`/`#229ED9`. |
| Unofficial status | Disclosed in onboarding, About, README, and App Store copy if published. |

### A flag worth raising, not burying

The `-gram` suffix sits in a crowded space alongside existing third-party
clients (Swiftgram, Nicegram) and unrelated products (Instagram). It does not
use the "Telegram" mark and precedent is reasonably well established, so the
risk is low — but it is **not zero**, because the suffix plus the messaging
category can suggest association. The mitigations above (no plane, no blue
circle, explicit unofficial disclosure) are what keep that risk low, so they are
requirements rather than nice-to-haves. If you want the risk closer to zero, the
lever is the name itself, and now — before any branding work — is the cheapest
moment to pull it. I am proceeding with **Nodogram** as instructed.

I am not a lawyer and this is not legal advice. If Nodogram is ever
commercialised or widely distributed, have counsel review this section.

---

## 6. Open decision: Nodogram's own license

Path A leaves this genuinely free. Deferred to you; it does not block Phase 2+.

| Option | Effect |
|---|---|
| **MIT / Apache-2.0** | Maximum reuse; others may make closed forks. Apache-2.0 adds a patent grant. |
| **GPL-3.0** | Forks must stay open. **Forfeits App Store distribution** (§1). |
| **Source-available / proprietary** | Permitted by BSL-1.0 + MIT. Must still ship §4 notices. |

Until you decide, the repository carries **no** `LICENSE` file — deliberately,
so that no license is implied by accident. Under default copyright this means
"all rights reserved"; nothing is lost by waiting.

---

## 7. Compliance checklist (gate for any release)

- [ ] `api_id` / `api_hash` supplied via git-ignored `Secrets.xcconfig`
- [ ] `git log -p` contains no credential; history audited, not just HEAD
- [ ] `THIRD_PARTY_NOTICES.md` present and complete
- [ ] In-app Acknowledgements screen renders those notices
- [ ] No file copied from `TelegramSwift` / `tdesktop` (audit: §2.2 boundary)
- [ ] Icon contains no paper plane and no blue circle
- [ ] "Unofficial / not affiliated" disclosure visible in onboarding and About
- [ ] `UPSTREAM.md` records exact pinned versions
- [ ] Nodogram's own license chosen and `LICENSE` added (§6)

---

*Verified 2026-10-01 against upstream sources. Revisit when `UPSTREAM.md` pins change.*
