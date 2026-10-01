# Nodogram

A fast, private, keyboard-first **macOS** messenger built on
[TDLib](https://github.com/tdlib/td) — with the message history, drafts, and
search that Telegram never gave you.

> **Nodogram is an independent, unofficial client.** It is not affiliated with,
> endorsed by, or sponsored by Telegram Messenger LLP. It does not use the
> Telegram name, logo, or branding.

**Status: Phase 1 complete — architecture and analysis.** No application code
yet, by design. The foundation was verified by building and running against real
TDLib before committing to a design.

---

## What makes it different

| | Telegram | Nodogram |
|---|---|---|
| Drafts | One per chat, easily lost | Durable, with version history |
| Deleted messages | Gone from your view too | Optional local archive — opt-in, encrypted |
| Read times | "Read", rarely precise | Exact server time, with honest fallbacks |
| Search | Mostly server-side | Instant local FTS over notes, drafts, archive + operators |

---

## Documentation — read in this order

| Document | What it covers |
|---|---|
| [ARCHITECTURE.md](Documentation/ARCHITECTURE.md) | Verified findings, layering, the four differentiating subsystems, limitations, phases |
| [PRODUCT_SPEC.md](Documentation/PRODUCT_SPEC.md) | Positioning, features, performance targets, and what we deliberately don't do |
| [DATA_MODEL.md](Documentation/DATA_MODEL.md) | Local-only schema, migrations, FTS5 |
| [SECURITY_MODEL.md](Documentation/SECURITY_MODEL.md) | Threat model, key hierarchy, archive risk |
| [LEGAL_AND_LICENSES.md](Documentation/LEGAL_AND_LICENSES.md) | License decision record, attribution, trademark |
| [UPSTREAM.md](Documentation/UPSTREAM.md) | Pinned versions and the upgrade procedure |
| [DECISIONS.md](Documentation/DECISIONS.md) | Settled decisions and their consequences |

---

## Foundation

Built on TDLib rather than forked from Telegram's own macOS client. That choice
is deliberate and documented in [LEGAL_AND_LICENSES.md](Documentation/LEGAL_AND_LICENSES.md) §1:
forking the GPL-licensed client would force Nodogram's license and block Mac App
Store distribution.

| Dependency | Version | License |
|---|---|---|
| TDLib | 1.8.67 (MTProto layer 229) | Boost Software License 1.0 |
| TDLibKit | `1.5.2-tdlib-1.8.67-0efabf93` | MIT |
| TDLibFramework | `1.8.67-0efabf93` | MIT |
| GRDB.swift | 7.11.0 | MIT |

Verified on macOS 26.5, Xcode 26.6, Swift 6.3.3, Apple M1 Pro.

---

## Requirements

- macOS 14+ (development on 26.5)
- Xcode 26+ / Swift 6.3+
- Apple Silicon or Intel
- A Telegram account

---

## Setup

### 1. Telegram API credentials

Get your **own** `api_id` and `api_hash` at
**[my.telegram.org](https://my.telegram.org)** → *API development tools*.

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Then edit `Config/Secrets.xcconfig`:

```
TELEGRAM_API_ID   = 1234567
TELEGRAM_API_HASH = 0123456789abcdef0123456789abcdef
```

> **Never commit this file.** It is git-ignored. Telegram warns that publishing
> credentials triggers `API_ID_PUBLISHED_FLOOD` errors *for your users*.
> One `api_id` per phone number.

### 2. Code signing

```bash
cp Config/Signing.example.xcconfig Config/Signing.xcconfig
```

Then edit it with your Apple **Team ID** (10 characters, from
[developer.apple.com](https://developer.apple.com/account) → Membership) and a
bundle identifier you control:

```
DEVELOPMENT_TEAM          = ABCDE12345
PRODUCT_BUNDLE_IDENTIFIER = com.yourcompany.nodogram
```

Signing is only required to run a bundled `.app` (notifications, Keychain,
sandbox entitlements). It is not needed to build and test the core libraries.

### 3. Build

Available from Phase 2. The first build downloads a ~300 MB TDLib xcframework.

---

## Repository layout

```
Nodogram/
  App/            entry point, menus, windows
  Features/       one folder per feature (View + ViewModel)
  Domain/         models, use cases, repository protocols  — no TDLib types
  Core/           Database, Security, Search, Synchronization, Concurrency
  Telegram/       Gateway/ + Mapping/  ← the ONLY TDLib-aware code
  UI/             Components, Theme, Accessibility
  Platform/macOS/ notifications, Quick Look, Spotlight, Share
  Resources/      assets + Localizations (en, uz-Latn, uz-Cyrl, ru)
Tests/            Unit, Integration, UITests
Documentation/    architecture, spec, data model, security, legal, upstream
Config/           xcconfig (real secrets git-ignored)
Tools/            build & maintenance scripts
```

The layering rule is enforced, not merely encouraged: `Nodogram/Domain` must
compile with TDLibKit removed from the package graph.

---

## Known limitations

Stated up front rather than discovered later:

- **No voice/video calls in v1.** TDLib provides call *signalling* only; real
  calls need the `tgcalls`/WebRTC media stack. See
  [ARCHITECTURE.md](Documentation/ARCHITECTURE.md) §10.1.
- **The local archive cannot recover messages this device never received**, and
  does not bypass server-side deletion. It retains only what Nodogram actually
  got, and only if you opt in.
- **Read times are only as precise as Telegram allows.** Telegram enforces
  reciprocity, and old read times expire server-side. Both are shown honestly
  rather than faked.
- Cached media files rely on FileVault rather than per-file encryption
  ([SECURITY_MODEL.md](Documentation/SECURITY_MODEL.md) §4).

---

## License

**Not yet chosen** — deliberately. TDLib (BSL-1.0) and the MIT wrappers leave
this open, and no `LICENSE` file is present so that nothing is implied by
accident. See [LEGAL_AND_LICENSES.md](Documentation/LEGAL_AND_LICENSES.md) §6.

Third-party notices will ship in `Documentation/THIRD_PARTY_NOTICES.md` and in
Settings → About → Acknowledgements.
