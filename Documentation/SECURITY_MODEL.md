# Nodogram — Security Model

**Phase 1 deliverable.** Scope: the local security of a Telegram client on macOS.

---

## 1. Principles

1. **No custom cryptography.** We use TDLib's reviewed MTProto implementation,
   SQLCipher, Apple's Keychain, and CryptoKit. We write no cipher, no KDF, no
   protocol. (Brief §34.)
2. **The threat we can actually address is local.** Transport security is
   TDLib's. Ours is data at rest on this Mac.
3. **Local-only features are the main new risk.** Draft history and the deleted-
   message archive exist *because* the user wants retention — which means
   Nodogram deliberately keeps data that Telegram would have discarded. That is
   a privacy liability we create, so we own it explicitly.
4. **No telemetry.** No message content, drafts, notes, or archives leave the
   device except to Telegram as the protocol requires. (Brief §70.)
5. **Honest claims only.** We never imply protection we do not provide.

---

## 2. Threat model

### In scope

| Threat | Mitigation |
|---|---|
| Device theft / offline disk access | FileVault (OS) + SQLCipher on our DB + encrypted TDLib DB; keys in Keychain |
| Another local user account | POSIX perms + Keychain ACL + per-account key separation |
| Shoulder-surfing / unattended Mac | App lock (passcode / Touch ID), configurable timeout |
| Casual process snooping | Keys never written to disk by us; no plaintext DB; no secrets in logs |
| Credential leak via git | Secrets in git-ignored xcconfig + Keychain; CI secret scan |
| Accidental retention | Archive opt-in, scoped, retention-limited, one-action erase |
| Cross-account leakage | Separate dirs, DBs, keys, indexes per account |
| Plaintext escaping to system indexes | Message-body Spotlight indexing opt-in, **off by default** |

### Explicitly out of scope — stated, not hidden

| Threat | Why |
|---|---|
| Compromised macOS / root / kernel malware | Root can read our memory and Keychain once unlocked. No app-level defence is honest here. |
| The recipient's device | We cannot control what the other side retains or screenshots. |
| Telegram's servers | Server-side behaviour is outside our trust boundary and not auditable by us. |
| Targeted forensics on an unlocked Mac | Keys are necessarily in memory while the app runs. |
| Screen capture by other apps | macOS has no app-level prevention we can rely on. |

---

## 3. Key hierarchy

```
Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly, ACL-gated)
├── nodogram.account.<uuid>.tdlib-db-key      → TDLib database encryption
├── nodogram.account.<uuid>.local-db-key      → SQLCipher (our GRDB database)
├── nodogram.account.<uuid>.archive-key       → archive content column encryption
└── nodogram.applock.verifier                 → app-lock credential verifier
```

Rules:

- Keys are generated with `SecRandomCopyBytes` and **never leave the Keychain**
  except into process memory at unlock.
- `…ThisDeviceOnly` — keys must not sync to iCloud.
- **Per-account separation**: one account's key cannot open another's data.
- The archive gets its **own** key so "erase archive" can be made cryptographic
  (destroy the key) rather than relying on row deletion alone.
- App lock stores a **verifier**, never the password itself.
- No key, token, or phone number is ever logged. Log redaction is a test case.

---

## 4. Data at rest

| Store | Encryption | Key |
|---|---|---|
| TDLib database (remote data) | TDLib's own, via `setTdlibParameters(database_encryption_key:)` | `tdlib-db-key` |
| Nodogram database (local-only) | SQLCipher (AES-256) | `local-db-key` |
| Archived message content | SQLCipher + per-column envelope | `archive-key` |
| Cached media / thumbnails | Not individually encrypted — relies on FileVault | — |
| Preferences | `UserDefaults`, non-sensitive only | — |

**Deliberate limitation, disclosed in the Privacy Center:** cached media files
are not individually encrypted. Encrypting every thumbnail would make scrolling
unacceptably slow, and the honest mitigation is FileVault. Users who need media
encrypted at rest are told to enable FileVault. We state this rather than
implying full-disk-level protection we do not provide.

---

## 5. App lock (brief §35)

Modes: none · password · passcode · Touch ID (`LocalAuthentication`).

Triggers: immediately · after 1 / 5 / 15 min · on sleep · on screen lock.

On lock: in-memory keys are zeroed where the language permits, databases are
closed, and window contents are obscured. Unlock re-derives access via Keychain.
Touch ID is a **gate on Keychain release**, not a bypass of it. Failed attempts
are rate-limited with backoff.

> Honest note: Swift gives no guaranteed-zeroing primitive for `String`. Key
> material is held in `Data`/`SymmetricKey` and explicitly overwritten; we do
> not claim perfect scrubbing of every transient copy.

---

## 6. Local archive — the highest-risk feature

The archive can contain messages the sender believed were deleted. It is the
most sensitive store in the app, so it carries the strictest controls:

1. **Off by default.**
2. **Explicit informed consent** before enabling, in plain language:
   > Messages preserved here are stored locally on this Mac. Anyone with access
   > to this account or device may be able to read them. This setting does not
   > bypass server-side deletion and cannot recover messages that were never
   > received by this device.
3. **"Forever" requires a second, separate confirmation.**
4. Scoped: private chats / groups / channels / all.
5. Retention: 24 h · 7 d · 30 d · 1 y · forever, enforced by a scheduled purge.
6. Encrypted with its own key (§3).
7. **Erase archive** is one action and destroys the key, not merely the rows.
8. Never silently reinserted into a live conversation.
9. Fully enumerated in the Privacy Center (brief §36).

> This feature is lawful to build and is the user's choice to enable, but it
> changes the privacy expectations of people messaging them. Keeping it
> off-by-default, scoped, and clearly explained is the design taking that
> seriously rather than hiding behind a toggle.

---

## 7. Secrets handling (brief §82)

| Secret | Where |
|---|---|
| Telegram `api_id` / `api_hash` | `Config/Secrets.xcconfig` — **git-ignored** |
| Apple Team ID / bundle id | `Config/Signing.xcconfig` — git-ignored |
| Signing certificates | Keychain / Xcode, never in-repo |
| Database keys | Keychain, generated at runtime |

`Config/Secrets.example.xcconfig` is committed as the template.
`.gitignore` excludes the real files. CI runs a secret scan, and release gating
includes `git log -p` history audit — not just a check of HEAD, since a
credential committed once stays in history.

---

## 8. Network security

Delegated to TDLib, deliberately: MTProto 2.0, certificate handling, and
transport obfuscation are implemented and reviewed there. We do not wrap, proxy,
or second-guess it.

Our additions: no third-party network calls whatsoever; link previews are fetched
by TDLib, not by us; downloaded content is **never** executed or auto-opened
(brief §61).

---

## 9. Verification plan

Security claims in this document become tests in Phase 17 and Phase 22:

- Keychain items are `ThisDeviceOnly` and ACL-gated.
- DB files are unreadable without the key (open with wrong key must fail).
- Account A's key cannot decrypt account B's database.
- App lock blocks access after each trigger.
- "Erase archive" leaves no recoverable plaintext.
- Logs contain no keys, tokens, phone numbers, or message content.
- Secret scan passes against full git history.
- Retention purge actually deletes on schedule.

A claim in this document without a corresponding passing test is treated as
unverified and must not be repeated in user-facing copy.

---

*Companion documents: `ARCHITECTURE.md`, `PRODUCT_SPEC.md`, `LEGAL_AND_LICENSES.md`.*
